import 'dart:convert';
import 'dart:typed_data';

import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteFileSession _session() => RemoteFileSession(
      host: 'h',
      port: 22,
      username: 'u',
      secret: 's',
      path: '/logs/app.log',
      mode: RemoteFileMode.follow,
    );

void _feed(RemoteFileSession session, Iterable<String> lines) {
  session.buffer.append(
    Uint8List.fromList(utf8.encode('${lines.join('\n')}\n')),
  );
}

void main() {
  test('清空 hides existing lines; later output is the visible content', () {
    final session = _session();
    _feed(session, ['old1', 'old2', 'old3']);
    expect(session.visibleLineCount, 3);

    session.clearView();
    expect(session.visibleLineCount, 0);
    expect(session.viewClearedAt, 3);

    _feed(session, ['fresh1', 'fresh2']);
    expect(session.visibleLineCount, 2);
    expect(session.buffer.lineAt(session.visibleStart), 'fresh1');
    // The buffer itself still holds the pre-clear lines (复制全部 skips them;
    // 下载 always fetches the full remote file regardless).
    expect(session.buffer.length, 5);
  });

  test('the 清空 marker clamps once the ring rotates past it', () {
    final session = _session();
    _feed(session, ['a', 'b', 'c']);
    session.clearView();

    // Enough lines to evict past the marker (capacity 10000, chunks of 64).
    _feed(session, List.generate(10062, (i) => 'line$i'));
    expect(session.buffer.firstRetained, greaterThan(session.viewClearedAt));
    expect(session.visibleStart, 0);
    expect(session.visibleLineCount, session.buffer.length);
  });
}
