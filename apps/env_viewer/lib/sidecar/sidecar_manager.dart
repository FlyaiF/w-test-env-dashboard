import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SidecarManager extends ChangeNotifier {
  Process? _process;
  int? _port;
  bool _connected = false;
  String? _error;

  bool get connected => _connected;
  int? get port => _port;
  String? get error => _error;
  String get baseUrl => 'http://127.0.0.1:$_port';

  Future<void> start(String dsn) async {
    await stop();
    _error = null;

    final binaryPath = _resolveBinaryPath();
    debugPrint('[sidecar] binary=$binaryPath');
    final file = File(binaryPath);
    if (!await file.exists()) {
      _error = '找不到后端服务: $binaryPath';
      notifyListeners();
      return;
    }

    try {
      _process = await Process.start(binaryPath, ['--dsn', dsn]);

      // Monitor for unexpected exit
      _process!.exitCode.then((code) {
        if (_connected) {
          _connected = false;
          _error = '后端服务意外退出 (code: $code)';
          notifyListeners();
        }
      });

      // Capture stderr for error reporting
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[sidecar stderr] $data');
        if (data.contains('DB_ERROR=')) {
          _error = data.replaceFirst('DB_ERROR=', '').trim();
        }
      });

      // Read stdout line by line, waiting for PORT=<n>
      final completer = Completer<int>();
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            debugPrint('[sidecar] $line');
            if (!completer.isCompleted && line.startsWith('PORT=')) {
              final p = int.tryParse(line.substring(5));
              if (p != null) completer.complete(p);
            }
          });

      _port = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('后端服务启动超时'),
      );

      _connected = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _connected = false;
      await stop();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        _process!.kill(ProcessSignal.sigkill);
      }
      _process = null;
      _port = null;
      _connected = false;
    }
  }

  Future<void> restart(String dsn) async {
    await stop();
    await start(dsn);
  }

  Future<String> testConnection(String dsn) async {
    final binaryPath = _resolveBinaryPath();
    final file = File(binaryPath);
    if (!await file.exists()) {
      throw StateError('找不到后端服务: $binaryPath');
    }

    final result = await Process.run(binaryPath, [
      '--test-dsn',
      dsn,
    ]).timeout(const Duration(seconds: 20));

    if (result.exitCode == 0) {
      return 'connection successful';
    }

    final stderr = (result.stderr as String).trim();
    final stdout = (result.stdout as String).trim();
    final message = stderr.isNotEmpty ? stderr : stdout;
    throw StateError(
      message.replaceFirst('DB_ERROR=', '').trim().isEmpty
          ? '连接失败'
          : message.replaceFirst('DB_ERROR=', '').trim(),
    );
  }

  String _resolveBinaryPath() {
    final exe = Platform.resolvedExecutable;

    if (kDebugMode) {
      return _devBinaryPath();
    }

    if (Platform.isMacOS) {
      // In .app bundle: Contents/Resources/go_sidecar
      final contentsIdx = exe.indexOf('/Contents/');
      if (contentsIdx != -1) {
        return '${exe.substring(0, contentsIdx)}/Contents/Resources/go_sidecar';
      }
      // Dev mode: binary next to the go_sidecar project
      return _devBinaryPath();
    } else if (Platform.isWindows) {
      final dir = File(exe).parent.path;
      return '$dir/data/go_sidecar.exe';
    } else {
      // Linux
      final dir = File(exe).parent.path;
      return '$dir/data/go_sidecar';
    }
  }

  String get _sidecarExecutableName =>
      Platform.isWindows ? 'go_sidecar.exe' : 'go_sidecar';

  String _devBinaryPath() {
    // In dev mode, look for the Go binary built locally
    // Navigate from apps/env_viewer/.dart_tool/... up to project root
    final binaryName = _sidecarExecutableName;
    var dir = Directory(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 10; i++) {
      final candidates = [
        File('${dir.path}/apps/env_viewer/go_sidecar/$binaryName'),
        File('${dir.path}/go_sidecar/$binaryName'),
        File('${dir.path}/build/sidecar/$binaryName'),
        File('${dir.path}/build/sidecar/go_sidecar'),
      ];
      for (final candidate in candidates) {
        if (candidate.existsSync()) return candidate.path;
      }
      dir = dir.parent;
    }
    // Fallback: relative to CWD
    final cwd = Directory.current.path;
    final cwdCandidates = [
      File('$cwd/go_sidecar/$binaryName'),
      File('$cwd/apps/env_viewer/go_sidecar/$binaryName'),
    ];
    for (final candidate in cwdCandidates) {
      if (candidate.existsSync()) return candidate.path;
    }
    return cwdCandidates.first.path;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
