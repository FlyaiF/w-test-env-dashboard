import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'log_file_store.dart';

class SshLogSession {
  SSHClient? _client;
  SSHSession? _session;
  final _logController = StreamController<String>.broadcast();
  final _statusController = StreamController<SshSessionStatus>.broadcast();
  bool _disposed = false;
  SshSessionStatus status = SshSessionStatus.connecting;
  LogFileStore? _logStore;
  final List<String> _tailWindow = [];
  static const int tailWindowSize = 500;

  Stream<String> get logStream => _logController.stream;
  Stream<SshSessionStatus> get statusStream => _statusController.stream;
  List<String> get buffer => List.unmodifiable(_tailWindow);
  int get totalLineCount => _logStore?.totalLines ?? 0;

  Future<List<String>> readLineRange(int start, int end) async {
    return await _logStore?.readLines(start, end) ?? [];
  }

  Future<String> readAllText() async {
    return await _logStore?.readAllText() ?? '';
  }

  final String host;
  final int port;
  final String logPath;

  SshLogSession({
    required this.host,
    required this.port,
    required this.logPath,
  });

  Future<void> connect({
    required String username,
    required String password,
  }) async {
    status = SshSessionStatus.connecting;
    _statusController.add(SshSessionStatus.connecting);
    try {
      if (logPath.trim().isEmpty) {
        throw ArgumentError('日志路径为空');
      }

      _logStore = await LogFileStore.create();
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      _session = await _client!.execute(
        'tail -n 200 -f ${_shellQuote(logPath)}',
      );

      status = SshSessionStatus.connected;
      _statusController.add(SshSessionStatus.connected);

      _session!.stdout.listen(
        (data) {
          if (_disposed) return;
          final text = utf8.decode(data, allowMalformed: true);
          _addLines(text);
        },
        onDone: () {
          if (!_disposed) {
            status = SshSessionStatus.disconnected;
            _statusController.add(SshSessionStatus.disconnected);
          }
        },
        onError: (e) {
          if (!_disposed) {
            _logController.add('[ERROR] $e');
            status = SshSessionStatus.error;
            _statusController.add(SshSessionStatus.error);
          }
        },
      );

      _session!.stderr.listen((data) {
        if (_disposed) return;
        final text = utf8.decode(data, allowMalformed: true);
        _addLines('[STDERR] $text');
      });
    } catch (e) {
      status = SshSessionStatus.error;
      _statusController.add(SshSessionStatus.error);
      _logController.add('[连接失败] $e');
      rethrow;
    }
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  void _addLines(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      _logStore?.appendLine(line);
      _tailWindow.add(line);
      if (_tailWindow.length > tailWindowSize) {
        _tailWindow.removeAt(0);
      }
      _logController.add(line);
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    try {
      _session?.kill(SSHSignal.TERM);
    } catch (_) {}
    _client?.close();
    await _logStore?.dispose();
    _logStore = null;
    _tailWindow.clear();
    status = SshSessionStatus.disconnected;
    _statusController.add(SshSessionStatus.disconnected);
    await _logController.close();
    await _statusController.close();
  }
}

enum SshSessionStatus { connecting, connected, disconnected, error }
