import 'dart:convert';
import 'dart:typed_data';

import 'package:env_viewer/services/remote_file/line_buffer.dart';
import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

List<String> allLines(LineBuffer buffer) =>
    [for (var i = 0; i < buffer.length; i++) buffer.lineAt(i)];

void main() {
  test('splits chunks into lines across arbitrary chunk boundaries', () {
    final buffer = LineBuffer();
    buffer.append(bytes(utf8.encode('first li')));
    buffer.append(bytes(utf8.encode('ne\nsecond\nthi')));
    buffer.append(bytes(utf8.encode('rd\n')));

    expect(allLines(buffer), ['first line', 'second', 'third']);
  });

  test('tolerates CRLF and preserves empty lines', () {
    final buffer = LineBuffer();
    buffer.append(bytes(utf8.encode('a\r\n\r\nb\n')));

    expect(allLines(buffer), ['a', '', 'b']);
  });

  test('flush commits a trailing unterminated line', () {
    final buffer = LineBuffer();
    buffer.append(bytes(utf8.encode('no newline')));
    expect(buffer.length, 0);

    buffer.flush();
    expect(allLines(buffer), ['no newline']);
  });

  test('decodes a multibyte UTF-8 character split across chunks', () {
    final encoded = utf8.encode('前缀 中文 后缀\n');
    final buffer = LineBuffer();
    // Split inside the bytes of a CJK character.
    buffer.append(bytes(encoded.sublist(0, 8)));
    buffer.append(bytes(encoded.sublist(8)));

    expect(allLines(buffer), ['前缀 中文 后缀']);
  });

  test('switching encoding re-decodes buffered bytes', () {
    // GBK bytes for 中文.
    final gbkLine = bytes([0xD6, 0xD0, 0xCE, 0xC4, 0x0A]);
    final buffer = LineBuffer();
    buffer.append(gbkLine);

    final asUtf8 = buffer.lineAt(0);
    expect(asUtf8, isNot('中文')); // Mojibake under UTF-8.

    buffer.encoding = RemoteFileEncoding.gbk;
    expect(buffer.lineAt(0), '中文');

    buffer.encoding = RemoteFileEncoding.utf8;
    expect(buffer.lineAt(0), asUtf8);
  });

  test('drops oldest lines beyond capacity but keeps the total count', () {
    final buffer = LineBuffer(capacity: 3);
    for (var i = 1; i <= 5; i++) {
      buffer.append(bytes(utf8.encode('line$i\n')));
    }

    expect(allLines(buffer), ['line3', 'line4', 'line5']);
    expect(buffer.totalAppended, 5);
  });

  test('shellQuote survives spaces and single quotes', () {
    expect(shellQuote('/var/log/app.log'), "'/var/log/app.log'");
    expect(shellQuote("/tmp/a b'c.log"), "'/tmp/a b'\\''c.log'");
  });
}
