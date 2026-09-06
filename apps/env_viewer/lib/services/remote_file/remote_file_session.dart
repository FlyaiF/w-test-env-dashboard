import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'line_buffer.dart';

/// How a remote file is opened: 跟随 streams appended lines (`tail -f`);
/// 查看 reads the current content once (refreshable).
enum RemoteFileMode { follow, view }

enum RemoteFileStatus { connecting, connected, disconnected, failed }

/// 查看 mode reads at most this many bytes; larger files show a truncation
/// notice and offer 下载 instead.
const int kViewModeByteCap = 2 * 1024 * 1024;

/// One live SSH session onto one remote file, read-only (PRD: the viewer
/// observes; changing files stays in the user's own SSH tools).
///
/// The brokered secret is held in memory only for this object's lifetime — it
/// enables 重连 without re-brokering — and is never written anywhere
/// (ADR-0009).
class RemoteFileSession extends ChangeNotifier {
  final String host;
  final int port;
  final String username;
  final String _secret;
  final String path;
  final RemoteFileMode mode;

  final LineBuffer buffer;

  RemoteFileStatus status = RemoteFileStatus.connecting;

  /// Localized reason for a failed/disconnected status, or null.
  String? statusDetail;

  /// 查看 mode only: the file exceeded [kViewModeByteCap] and was cut short.
  bool truncated = false;

  /// 跟随 mode: freeze notifications while the user reads; bytes keep
  /// buffering so nothing is missed.
  bool paused = false;

  /// 清空: absolute line number before which lines are hidden from the view
  /// and from 复制全部. A view marker, DevTools-style — the buffer keeps
  /// rotating underneath and the remote file is untouched, so after a clear
  /// the visible/copyable content is exactly the output that arrived since.
  int viewClearedAt = 0;

  SSHClient? _client;
  SSHSession? _tail;
  bool _disposed = false;
  int _generation = 0;

  RemoteFileSession({
    required this.host,
    required this.port,
    required this.username,
    required String secret,
    required this.path,
    required this.mode,
    int bufferCapacity = 10000,
  }) : _secret = secret,
       buffer = LineBuffer(capacity: bufferCapacity);

  RemoteFileEncoding get encoding => buffer.encoding;

  set encoding(RemoteFileEncoding value) {
    if (buffer.encoding == value) return;
    buffer.encoding = value;
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void clearView() {
    viewClearedAt = buffer.totalAppended;
    notifyListeners();
  }

  /// First buffer index the viewer should render — the 清空 marker, clamped
  /// to what the ring still retains.
  int get visibleStart {
    final start = viewClearedAt - buffer.firstRetained;
    if (start < 0) return 0;
    return start > buffer.length ? buffer.length : start;
  }

  int get visibleLineCount => buffer.length - visibleStart;

  Future<void> connect() async {
    final generation = ++_generation;
    _closeTransport();
    buffer.clear();
    viewClearedAt = 0;
    truncated = false;
    _setStatus(RemoteFileStatus.connecting, detail: null);
    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
      final client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => _secret,
      );
      if (_stale(generation)) {
        client.close();
        return;
      }
      _client = client;
      switch (mode) {
        case RemoteFileMode.follow:
          await _startTail(client, generation);
        case RemoteFileMode.view:
          await _readOnce(client, generation);
      }
    } on SSHAuthFailError {
      _fail(generation, 'SSH 认证失败，请检查用户名和密码');
    } on TimeoutException {
      _fail(generation, '连接超时（$host:$port）');
    } on SocketException catch (e) {
      _fail(generation, '无法连接 $host:$port（${e.osError?.message ?? e.message}）');
    } catch (e) {
      _fail(generation, '连接失败：$e');
    }
  }

  /// Re-run the whole session: fresh tail (follow) or fresh read (view).
  Future<void> reconnect() => connect();

  /// Entry names in [dirPath] over this session's live connection, directories
  /// suffixed with `/`. Used to autocomplete sibling paths in the 日志文件
  /// free-path bar. Empty when not connected or the listing fails — completion
  /// is best-effort and must never surface a connection error of its own.
  Future<List<String>> listDirectory(String dirPath) async {
    final client = _client;
    if (client == null || _disposed) return const [];
    try {
      final sftp = await client.sftp();
      final entries = await sftp.listdir(dirPath);
      return [
        for (final e in entries)
          if (e.filename != '.' && e.filename != '..')
            e.attr.isDirectory ? '${e.filename}/' : e.filename,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _startTail(SSHClient client, int generation) async {
    final session = await client.execute(
      'tail -n 200 -f ${shellQuote(path)}',
    );
    if (_stale(generation)) {
      session.close();
      return;
    }
    _tail = session;
    _setStatus(RemoteFileStatus.connected);

    final stderr = BytesBuilder(copy: false);
    session.stderr.listen((chunk) => stderr.add(chunk));
    session.stdout.listen(
      (chunk) {
        if (_stale(generation)) return;
        buffer.append(Uint8List.fromList(chunk));
        if (!paused) notifyListeners();
      },
      onDone: () {
        if (_stale(generation)) return;
        buffer.flush();
        final err = utf8.decode(stderr.takeBytes(), allowMalformed: true).trim();
        if (buffer.isEmpty && err.isNotEmpty) {
          _setStatus(RemoteFileStatus.failed, detail: err);
        } else {
          _setStatus(
            RemoteFileStatus.disconnected,
            detail: err.isEmpty ? '连接已断开' : err,
          );
        }
      },
      onError: (Object e) {
        if (_stale(generation)) return;
        _setStatus(RemoteFileStatus.disconnected, detail: '连接中断：$e');
      },
    );
  }

  Future<void> _readOnce(SSHClient client, int generation) async {
    final sftp = await client.sftp();
    final file = await sftp.open(path);
    try {
      final size = (await file.stat()).size;
      truncated = size != null && size > kViewModeByteCap;
      final bytes = await file.readBytes(length: kViewModeByteCap);
      if (_stale(generation)) return;
      buffer.append(bytes);
      buffer.flush();
      _setStatus(RemoteFileStatus.connected);
    } finally {
      await file.close();
    }
  }

  /// 查看 mode: re-read the file over the existing connection (or reconnect
  /// if it dropped).
  Future<void> refresh() async {
    final client = _client;
    if (mode != RemoteFileMode.view || client == null || client.isClosed) {
      return connect();
    }
    final generation = ++_generation;
    buffer.clear();
    viewClearedAt = 0;
    truncated = false;
    _setStatus(RemoteFileStatus.connecting);
    try {
      await _readOnce(client, generation);
    } catch (e) {
      _fail(generation, '读取失败：$e');
    }
  }

  /// Stream the complete remote file to [localPath] over SFTP. [onProgress]
  /// reports (bytes written, total bytes or null when the size is unknown).
  Future<void> download(
    String localPath, {
    void Function(int written, int? total)? onProgress,
  }) async {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('会话未连接');
    }
    final sftp = await client.sftp();
    final file = await sftp.open(path);
    final sink = File(localPath).openWrite();
    try {
      final total = (await file.stat()).size;
      var written = 0;
      await for (final chunk in file.read()) {
        sink.add(chunk);
        written += chunk.length;
        onProgress?.call(written, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
      await file.close();
    }
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _fail(int generation, String message) {
    if (_stale(generation)) return;
    _setStatus(RemoteFileStatus.failed, detail: message);
  }

  void _setStatus(RemoteFileStatus next, {String? detail}) {
    status = next;
    statusDetail = detail;
    if (!_disposed) notifyListeners();
  }

  void _closeTransport() {
    _tail?.close();
    _tail = null;
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _closeTransport();
    super.dispose();
  }
}

/// Single-quote [value] for a POSIX shell so an arbitrary path survives
/// `tail -f` intact.
String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
