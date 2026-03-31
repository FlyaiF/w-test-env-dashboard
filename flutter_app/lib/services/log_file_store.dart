import 'dart:convert';
import 'dart:io';

class LogFileStore {
  final File _file;
  IOSink? _sink;
  final List<int> _lineOffsets = [];
  int _currentOffset = 0;
  bool _disposed = false;

  static int _counter = 0;

  LogFileStore._(this._file);

  static Future<LogFileStore> create() async {
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/ssh_log_${DateTime.now().millisecondsSinceEpoch}_${_counter++}.tmp',
    );
    await file.create();
    final store = LogFileStore._(file);
    store._sink = file.openWrite(mode: FileMode.writeOnly);
    return store;
  }

  int get totalLines => _lineOffsets.length;

  void appendLine(String line) {
    if (_disposed || _sink == null) return;
    final bytes = utf8.encode('$line\n');
    _lineOffsets.add(_currentOffset);
    _currentOffset += bytes.length;
    _sink!.add(bytes);
  }

  Future<List<String>> readLines(int start, int end) async {
    if (_disposed) return [];
    start = start.clamp(0, _lineOffsets.length);
    end = end.clamp(start, _lineOffsets.length);
    if (start >= end) return [];

    try {
      await _sink?.flush();

      final startOffset = _lineOffsets[start];
      final endOffset = end < _lineOffsets.length
          ? _lineOffsets[end]
          : _currentOffset;
      final length = endOffset - startOffset;

      final raf = await _file.open(mode: FileMode.read);
      try {
        await raf.setPosition(startOffset);
        final bytes = await raf.read(length);
        final text = utf8.decode(bytes, allowMalformed: true);
        return text.split('\n').where((l) => l.isNotEmpty).toList();
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return [];
    }
  }

  Future<String> readAllText() async {
    if (_disposed) return '';
    try {
      await _sink?.flush();
      return await _file.readAsString();
    } on FileSystemException {
      return '';
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      await _file.delete();
    } catch (_) {}
  }

  static Future<void> cleanOrphans() async {
    try {
      final dir = Directory.systemTemp;
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path.contains('ssh_log_') &&
            entity.path.endsWith('.tmp')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
