import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// Text encodings the remote file viewer can decode. Servers here are mostly
/// UTF-8; GBK is the per-tab fallback for the odd legacy file.
enum RemoteFileEncoding {
  utf8('UTF-8'),
  gbk('GBK');

  final String label;
  const RemoteFileEncoding(this.label);
}

/// One buffered line: raw bytes plus a decode cache for the current encoding.
class _Line {
  final Uint8List bytes;
  String? decoded;
  _Line(this.bytes);
}

/// Bounded line store for a streamed remote file. Bytes are split into lines
/// here (LF, tolerating CRLF) and kept raw so the encoding can be switched
/// after the fact — decoding happens lazily per line and is cached until the
/// encoding changes. Oldest lines fall off beyond [capacity], in whole
/// multiples of [evictionChunk].
class LineBuffer {
  final int capacity;

  /// Eviction granularity: oldest lines are dropped in whole multiples of
  /// this, so [firstRetained] is always a multiple. The viewer paragraphs
  /// lines in chunks of this same size anchored to absolute line numbers;
  /// whole-chunk eviction means a filled paragraph's text never changes —
  /// and Flutter only preserves a selection across rebuilds when the
  /// paragraph text is identical.
  final int evictionChunk;

  final List<_Line> _lines = [];
  final BytesBuilder _partial = BytesBuilder(copy: true);
  RemoteFileEncoding _encoding;
  bool _holdEviction = false;

  /// Total lines ever appended, including ones that fell off the ring.
  int totalAppended = 0;

  LineBuffer({
    this.capacity = 10000,
    this.evictionChunk = 64,
    RemoteFileEncoding encoding = RemoteFileEncoding.utf8,
  })  : assert(capacity >= evictionChunk),
        _encoding = encoding;

  int get length => _lines.length;
  bool get isEmpty => _lines.isEmpty;
  RemoteFileEncoding get encoding => _encoding;

  /// Absolute line number of `lineAt(0)` — always a multiple of
  /// [evictionChunk].
  int get firstRetained => totalAppended - _lines.length;

  /// While true the ring may grow beyond [capacity] instead of evicting —
  /// held during a selection drag so no rendered line shifts or disappears
  /// mid-gesture. Releasing evicts back down to [capacity].
  bool get holdEviction => _holdEviction;
  set holdEviction(bool value) {
    _holdEviction = value;
    if (!value) _evict();
  }

  set encoding(RemoteFileEncoding value) {
    if (value == _encoding) return;
    _encoding = value;
    for (final line in _lines) {
      line.decoded = null;
    }
  }

  /// Feed a raw chunk from the stream; chunk boundaries may fall mid-line or
  /// even mid-multibyte-character, so bytes accumulate until a LF arrives.
  void append(Uint8List chunk) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0x0A) {
        _partial.add(Uint8List.sublistView(chunk, start, i));
        _commitPartial();
        start = i + 1;
      }
    }
    if (start < chunk.length) {
      _partial.add(Uint8List.sublistView(chunk, start));
    }
  }

  /// Flush a trailing unterminated line (end of a static read, or stream end).
  void flush() {
    if (_partial.isNotEmpty) _commitPartial();
  }

  void clear() {
    _lines.clear();
    _partial.clear();
    totalAppended = 0;
  }

  void _commitPartial() {
    var bytes = _partial.takeBytes();
    if (bytes.isNotEmpty && bytes.last == 0x0D) {
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }
    _lines.add(_Line(bytes));
    totalAppended++;
    if (!_holdEviction) _evict();
  }

  void _evict() {
    if (_lines.length <= capacity) return;
    final excess = _lines.length - capacity;
    final remove = (excess + evictionChunk - 1) ~/ evictionChunk * evictionChunk;
    _lines.removeRange(0, remove);
  }

  /// Decoded line at [index] (0 = oldest retained), cached per encoding.
  String lineAt(int index) {
    final line = _lines[index];
    return line.decoded ??= _decode(line.bytes);
  }

  String _decode(Uint8List bytes) {
    switch (_encoding) {
      case RemoteFileEncoding.utf8:
        return utf8.decode(bytes, allowMalformed: true);
      case RemoteFileEncoding.gbk:
        try {
          return gbk.decode(bytes);
        } catch (_) {
          // Not valid GBK — fall back so a bad switch never crashes the view.
          return utf8.decode(bytes, allowMalformed: true);
        }
    }
  }
}
