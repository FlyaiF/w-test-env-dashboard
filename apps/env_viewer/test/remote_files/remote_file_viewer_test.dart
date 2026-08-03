import 'dart:convert';

import 'package:env_viewer/pages/remote_files/remote_file_viewer.dart';
import 'package:env_viewer/remote_files/remote_file_store.dart';
import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connected session pre-filled with [lines]; never dials SSH.
RemoteFileSession _sessionWith(List<String> lines) {
  final session = RemoteFileSession(
    host: 'h',
    port: 22,
    username: 'u',
    secret: 's',
    path: '/logs/app.log',
    mode: RemoteFileMode.view,
  );
  session.status = RemoteFileStatus.connected;
  session.buffer.append(
    Uint8List.fromList(utf8.encode('${lines.join('\n')}\n')),
  );
  session.buffer.flush();
  return session;
}

Widget _wrap(RemoteFileSession session) {
  return MaterialApp(
    home: Scaffold(
      body: RemoteFileViewer(
        tab: RemoteFileTab(serverId: 1, title: 'A · 应用', session: session),
      ),
    ),
  );
}

void main() {
  testWidgets('lines render as multi-line paragraphs, not one Text per line', (
    tester,
  ) async {
    final lines = List.generate(150, (i) => 'line $i');
    await tester.pumpWidget(_wrap(_sessionWith(lines)));

    // 150 lines at 64 per chunk = 3 paragraphs, of which the ListView builds
    // the visible ones — far fewer widgets than one Text per line, and each
    // paragraph holds real newlines so a cross-line selection copies with its
    // line breaks.
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SelectionArea),
            matching: find.byType(Text),
          ),
        )
        .toList();
    expect(texts, isNotEmpty);
    expect(texts.length, lessThan(150 ~/ 10));
    final first = texts.first.textSpan!.toPlainText();
    expect(first, contains('line 0\nline 1'));
    // Interior chunks end with the boundary newline that stitches copies.
    expect(first, endsWith('\n'));
  });

  testWidgets('复制全部 puts the whole buffer on the clipboard', (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_wrap(_sessionWith(['a', 'b', 'c'])));
    await tester.tap(find.byTooltip('复制全部'));
    await tester.pump();

    expect(copied.single!.split(RegExp(r'\r?\n')), ['a', 'b', 'c']);
    expect(find.text('已复制 3 行'), findsOneWidget);
  });
}
