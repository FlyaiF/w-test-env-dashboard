import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../api/backend_client.dart';
import '../../api/dto/client_update_dto.dart';

/// Client half of self-update (docs/client-update.md): a quiet startup check
/// against the backend, then — only when the user clicks 立即更新 — download,
/// SHA-256 verification, and handoff to the bundled updater helper, which swaps
/// the install after this process exits. The store never interrupts: an
/// available update only lights up the sidebar download icon.
class AppUpdateStore extends ChangeNotifier {
  final BackendClient _client;

  AppUpdateStore(this._client);

  ClientUpdateDto? _available;
  double _progress = 0;
  bool _busy = false;
  String? _error;

  /// Newer-than-running build offered by the backend, or null.
  ClientUpdateDto? get available => _available;

  /// Download progress 0..1 while [busy].
  double get progress => _progress;
  bool get busy => _busy;
  String? get error => _error;

  static String? get _platform {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  /// Startup poll. Silent on every failure — update availability is a bonus,
  /// never an error the user must deal with. Debug/profile builds skip it (a
  /// dev checkout must not offer to overwrite its own build output) unless
  /// ENV_VIEWER_FORCE_UPDATE_CHECK=1 forces it for end-to-end testing.
  Future<void> checkForUpdate() async {
    final platform = _platform;
    if (platform == null) return;
    final forced =
        Platform.environment['ENV_VIEWER_FORCE_UPDATE_CHECK'] == '1';
    if (!kReleaseMode && !forced) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final latest = await _client.latestClientUpdate(platform);
      if (latest != null && isNewerVersion(latest.version, info.version)) {
        _available = latest;
        notifyListeners();
      }
    } catch (_) {
      // Backend down or updates disabled: stay quiet.
    }
  }

  /// Downloads and verifies the offered zip, then launches the helper and
  /// exits the app. On any failure the app keeps running and [error] explains.
  Future<void> downloadAndRestart() async {
    final update = _available;
    final platform = _platform;
    if (update == null || platform == null || _busy) return;
    _busy = true;
    _error = null;
    _progress = 0;
    notifyListeners();

    Directory? workDir;
    try {
      final paths = _InstallPaths.locate(platform);
      workDir = Directory.systemTemp.createTempSync('env_viewer_update_');
      final zip = File('${workDir.path}${Platform.pathSeparator}${update.fileName}');

      await _client.downloadClientUpdate(
        platform: platform,
        version: update.version,
        destination: zip,
        onProgress: (received, total) {
          if (total > 0) {
            _progress = received / total;
            notifyListeners();
          }
        },
      );

      final digest = await sha256.bind(zip.openRead()).first;
      if (digest.toString() != update.sha256.toLowerCase()) {
        throw const BackendException('更新包校验失败，请重试');
      }

      // The helper must run from outside the install: the swap renames the
      // directory its bundled copy lives in.
      final helper = paths.copyHelperTo(workDir.path);
      await Process.start(
        helper,
        [
          '--wait-pid', '$pid',
          '--install-path', paths.installPath,
          '--zip', zip.path,
          '--platform', platform,
          '--log', _updaterLogPath(),
        ],
        // Never let the helper inherit this process's cwd: on Windows that is
        // the install directory, and a cwd lock there would make the helper's
        // own rename of the install fail.
        workingDirectory: workDir.path,
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } on BackendException catch (e) {
      _fail(workDir, e.message);
    } on _UpdateUnavailable catch (e) {
      _fail(workDir, e.message);
    } catch (e) {
      _fail(workDir, '更新失败: $e');
    }
  }

  void _fail(Directory? workDir, String message) {
    try {
      workDir?.deleteSync(recursive: true);
    } catch (_) {}
    _busy = false;
    _error = message;
    notifyListeners();
  }

  static String _updaterLogPath() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$home/.test-env-dashboard');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/updater.log';
  }

  /// True when [candidate] (x.y.z) is strictly newer than [running].
  /// Non-numeric segments compare as 0, so a malformed side never wins.
  static bool isNewerVersion(String candidate, String running) {
    List<int> parse(String v) => v
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .followedBy(const [0, 0, 0])
        .take(3)
        .toList();
    final a = parse(candidate);
    final b = parse(running);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Startup handshake with a running updater helper: when the helper launched
  /// us it passed a marker path; writing the file tells it this build started
  /// fine, so it commits the update instead of rolling back. Call once the UI
  /// has actually rendered a frame.
  static void signalStartedOkIfRequested() {
    final marker = Platform.environment['ENV_VIEWER_UPDATE_MARKER'];
    if (marker == null || marker.isEmpty) return;
    try {
      File(marker).writeAsStringSync('ok');
    } catch (_) {
      // Worst case the helper rolls back and the user just re-updates.
    }
  }
}

class _UpdateUnavailable implements Exception {
  final String message;
  const _UpdateUnavailable(this.message);
}

/// Resolves where this build is installed and where its bundled helper lives,
/// from Platform.resolvedExecutable.
class _InstallPaths {
  /// The directory the helper swaps: the .app bundle (macOS) or the folder
  /// holding env_viewer.exe (Windows).
  final String installPath;
  final String helperPath;

  const _InstallPaths(this.installPath, this.helperPath);

  static _InstallPaths locate(String platform) {
    final exe = File(Platform.resolvedExecutable);
    final _InstallPaths paths;
    if (platform == 'macos') {
      // .../env_viewer.app/Contents/MacOS/env_viewer
      final app = exe.parent.parent.parent;
      if (!app.path.endsWith('.app')) {
        throw const _UpdateUnavailable('当前不是安装版应用，无法自动更新');
      }
      paths = _InstallPaths(
        app.path,
        '${app.path}/Contents/Resources/env_viewer_updater',
      );
    } else {
      final dir = exe.parent.path;
      paths = _InstallPaths(
        dir,
        '$dir${Platform.pathSeparator}env_viewer_updater.exe',
      );
    }
    if (!File(paths.helperPath).existsSync()) {
      throw const _UpdateUnavailable('未找到更新助手，无法自动更新');
    }
    return paths;
  }

  /// Copies the helper into [dir] (outside the install) and returns its path.
  String copyHelperTo(String dir) {
    final name = helperPath.split(Platform.pathSeparator).last;
    final dest = '$dir${Platform.pathSeparator}$name';
    File(helperPath).copySync(dest);
    if (!Platform.isWindows) {
      // File.copySync does not carry the execute bit.
      Process.runSync('chmod', ['+x', dest]);
    }
    return dest;
  }
}
