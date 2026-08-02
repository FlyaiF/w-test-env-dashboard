/// Swap-and-rollback engine for env_viewer self-update.
///
/// The app downloads and SHA-verifies the release zip, copies this helper to a
/// temp location (its own copy inside the install would disappear mid-swap),
/// launches it detached, and exits. The helper then owns the install directory:
/// wait for the app to die, move the old install aside, unzip the new build
/// into place, relaunch, and judge success by a marker file the new app writes
/// after successful startup. No marker within the deadline means the new build
/// is broken on this machine — the helper restores the old install and
/// relaunches it, so a bad release never strands a user.
library;

import 'dart:io';

class UpdaterArgs {
  /// PID of the app instance that launched us; the swap waits for its exit.
  final int waitPid;

  /// The directory swapped wholesale: the `.app` bundle on macOS, the folder
  /// containing `env_viewer.exe` on Windows.
  final String installPath;

  final String zipPath;
  final String platform; // macos | windows
  final String logPath;

  const UpdaterArgs({
    required this.waitPid,
    required this.installPath,
    required this.zipPath,
    required this.platform,
    required this.logPath,
  });

  static UpdaterArgs parse(List<String> argv) {
    final values = <String, String>{};
    for (var i = 0; i + 1 < argv.length; i += 2) {
      final key = argv[i];
      if (!key.startsWith('--')) {
        throw FormatException('expected an --option, got "$key"');
      }
      values[key.substring(2)] = argv[i + 1];
    }
    String require(String name) {
      final value = values[name];
      if (value == null || value.isEmpty) {
        throw FormatException('missing required option --$name');
      }
      return value;
    }

    final platform = require('platform');
    if (platform != 'macos' && platform != 'windows') {
      throw FormatException('unsupported platform "$platform"');
    }
    return UpdaterArgs(
      waitPid: int.parse(require('wait-pid')),
      installPath: require('install-path'),
      zipPath: require('zip'),
      platform: platform,
      logPath: require('log'),
    );
  }
}

/// Process-level operations, injectable so [Updater] flows are testable with
/// real directories but without real app processes.
abstract class ProcessOps {
  Future<bool> isAlive(int pid);
  Future<void> extractZip(String zipPath, String destDir);

  /// Launch the app at [executable] detached; returns its PID.
  Future<int> launchApp(String executable, Map<String, String> environment);
  Future<void> killPid(int pid);
}

class SystemProcessOps implements ProcessOps {
  @override
  Future<bool> isAlive(int pid) async {
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      return (result.stdout as String).contains(' $pid ');
    }
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  }

  @override
  Future<void> extractZip(String zipPath, String destDir) async {
    // System extractors, not a Dart zip library: `ditto` preserves the
    // symlinks and executable bits inside a .app bundle, which pure-Dart
    // extraction silently loses.
    final result = Platform.isMacOS
        ? await Process.run('ditto', ['-xk', zipPath, destDir])
        : await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "$destDir" -Force',
          ]);
    if (result.exitCode != 0) {
      throw UpdaterException('解压失败: ${result.stderr}');
    }
  }

  @override
  Future<int> launchApp(String executable, Map<String, String> environment) async {
    final process = await Process.start(
      executable,
      const [],
      environment: environment,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  @override
  Future<void> killPid(int pid) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '$pid', '/F']);
    } else {
      await Process.run('kill', ['-9', '$pid']);
    }
  }
}

class UpdaterException implements Exception {
  final String message;
  const UpdaterException(this.message);

  @override
  String toString() => message;
}

class Updater {
  final UpdaterArgs args;
  final ProcessOps ops;
  final IOSink _log;

  /// Poll/deadline knobs, shrunk by tests.
  final Duration exitTimeout;
  final Duration startupTimeout;
  final Duration pollInterval;

  Updater(
    this.args,
    this.ops, {
    this.exitTimeout = const Duration(seconds: 60),
    this.startupTimeout = const Duration(seconds: 15),
    this.pollInterval = const Duration(milliseconds: 300),
  }) : _log = File(args.logPath).openWrite(mode: FileMode.append);

  Directory get _install => Directory(args.installPath);
  Directory get _backup => Directory('${args.installPath}.backup');
  Directory get _staging => Directory('${args.installPath}.staging');

  String get _appExecutable => args.platform == 'macos'
      ? '${args.installPath}/Contents/MacOS/env_viewer'
      : '${args.installPath}${Platform.pathSeparator}env_viewer.exe';

  /// After extraction, the directory that becomes the new install: the macOS
  /// zip wraps everything in `env_viewer.app/`, the Windows zip is loose files.
  Directory get _extractedRoot => args.platform == 'macos'
      ? Directory('${_staging.path}/env_viewer.app')
      : _staging;

  void log(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    _log.writeln(line);
    stdout.writeln(line);
  }

  /// Runs the whole update. Returns 0 on success, 1 on rollback, 2 when even
  /// the swap preparation failed (old install left untouched).
  Future<int> run() async {
    log('update start: pid=${args.waitPid} install=${args.installPath} '
        'zip=${args.zipPath} platform=${args.platform}');
    try {
      await _waitForAppExit();
      await _swapIn();
    } on Object catch (e) {
      // Nothing has replaced the install yet (or backup restore already ran):
      // report and leave whatever is in place runnable.
      log('update aborted before launch: $e');
      await _log.flush();
      return 2;
    }

    final ok = await _launchAndConfirm();
    if (ok) {
      await _cleanupAfterSuccess();
      log('update complete');
      await _log.flush();
      return 0;
    }

    await _rollback();
    await _log.flush();
    return 1;
  }

  Future<void> _waitForAppExit() async {
    final deadline = DateTime.now().add(exitTimeout);
    while (await ops.isAlive(args.waitPid)) {
      if (DateTime.now().isAfter(deadline)) {
        throw const UpdaterException('等待应用退出超时');
      }
      await Future<void>.delayed(pollInterval);
    }
    log('app pid ${args.waitPid} exited');
  }

  Future<void> _swapIn() async {
    if (!_install.existsSync()) {
      throw UpdaterException('安装目录不存在: ${args.installPath}');
    }
    if (_staging.existsSync()) _staging.deleteSync(recursive: true);
    await ops.extractZip(args.zipPath, _staging.path);
    if (!_extractedRoot.existsSync()) {
      _staging.deleteSync(recursive: true);
      throw UpdaterException('更新包内容不完整: 缺少 ${_extractedRoot.path}');
    }

    if (_backup.existsSync()) _backup.deleteSync(recursive: true);
    _install.renameSync(_backup.path);
    log('moved old install to ${_backup.path}');
    try {
      _extractedRoot.renameSync(args.installPath);
    } on Object {
      // Same-volume rename should not fail; if it does, put the old one back.
      _backup.renameSync(args.installPath);
      rethrow;
    }
    if (_staging.existsSync()) _staging.deleteSync(recursive: true);
    log('new build in place');
  }

  Future<bool> _launchAndConfirm() async {
    final marker = '${Directory.systemTemp.path}'
        '${Platform.pathSeparator}env_viewer_started_ok_$pid';
    final markerFile = File(marker);
    if (markerFile.existsSync()) markerFile.deleteSync();

    int launchedPid;
    try {
      launchedPid = await ops.launchApp(_appExecutable, {
        'ENV_VIEWER_UPDATE_MARKER': marker,
      });
    } on Object catch (e) {
      log('launch of new build failed: $e');
      return false;
    }
    log('launched new build pid=$launchedPid, waiting for marker');

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (markerFile.existsSync()) {
        markerFile.deleteSync();
        log('new build confirmed started');
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    log('no startup marker within $startupTimeout; assuming broken build');
    await ops.killPid(launchedPid);
    return false;
  }

  Future<void> _cleanupAfterSuccess() async {
    if (_backup.existsSync()) _backup.deleteSync(recursive: true);
    final zip = File(args.zipPath);
    if (zip.existsSync()) zip.deleteSync();
  }

  Future<void> _rollback() async {
    log('rolling back to previous version');
    if (_install.existsSync()) _install.deleteSync(recursive: true);
    _backup.renameSync(args.installPath);
    try {
      await ops.launchApp(_appExecutable, const {});
      log('previous version relaunched');
    } on Object catch (e) {
      log('relaunch of previous version failed: $e');
    }
  }
}
