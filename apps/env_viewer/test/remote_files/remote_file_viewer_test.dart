import 'dart:convert';

import 'package:env_viewer/pages/remote_files/remote_file_viewer.dart';
import 'package:env_viewer/remote_files/remote_file_store.dart';
import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session that can feed lines and notify like a live stream, without SSH.
class _TestSession extends RemoteFileSession {
  _TestSession({required super.mode})
    : super(
        host: 'h',
        port: 22,
        username: 'u',
        secret: 's',
        path: '/logs/app.log',
      );

  void feed(List<String> lines) {
    buffer.append(Uint8List.fromList(utf8.encode('${lines.join('\n')}\n')));
    notifyListeners();
  }
}

/// Connected session pre-filled with [lines]; never dials SSH.
_TestSession _sessionWith(
  List<String> lines, {
  RemoteFileMode mode = RemoteFileMode.view,
}) {
  final session = _TestSession(mode: mode);
  session.status = RemoteFileStatus.connected;
  session.feed(lines);
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

  testWidgets('清空 hides current output; 复制全部 then copies only fresh lines', (
    tester,
  ) async {
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

    final session = _sessionWith(
      ['old1', 'old2'],
      mode: RemoteFileMode.follow,
    );
    await tester.pumpWidget(_wrap(session));
    expect(find.textContaining('old1'), findsOneWidget);

    await tester.tap(find.byTooltip('清空显示'));
    await tester.pump();
    expect(find.text('已清空，等待新输出'), findsOneWidget);
    expect(find.textContaining('old1'), findsNothing);

    session.feed(['fresh1', 'fresh2']);
    await tester.pump();
    expect(find.textContaining('fresh1'), findsOneWidget);
    expect(find.textContaining('old1'), findsNothing);

    await tester.tap(find.byTooltip('复制全部'));
    await tester.pump();
    expect(copied.single!.split(RegExp(r'\r?\n')), ['fresh1', 'fresh2']);
    expect(find.text('已复制 2 行'), findsOneWidget);
  });

  testWidgets('chunks are keyed by absolute index as lines stream in', (
    tester,
  ) async {
    final session = _sessionWith(
      List.generate(100, (i) => 'line $i'),
      mode: RemoteFileMode.follow,
    );
    await tester.pumpWidget(_wrap(session));
    // Chunk 0 sits beyond the reversed viewport's cache and stays unbuilt —
    // the newest chunk (lines 64..99) is what hugs the bottom.
    expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);
    expect(find.byKey(const ValueKey<int>(0)), findsNothing);

    // Crossing the 64-line chunk boundary adds chunk 2; existing chunks keep
    // their identity (and with it, any live selection).
    session.feed(List.generate(30, (i) => 'line ${100 + i}'));
    await tester.pump();
    expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);
    expect(find.byKey(const ValueKey<int>(2)), findsOneWidget);
  });

  testWidgets('a selection drag holds ring eviction until release', (
    tester,
  ) async {
    final session = _sessionWith(List.generate(20, (i) => 'line $i'));
    await tester.pumpWidget(_wrap(session));

    final paragraph = tester.getCenter(find.byType(SelectionArea));
    final gesture = await tester.startGesture(
      paragraph - const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(paragraph + const Offset(60, 4));
    await tester.pump();
    expect(session.buffer.holdEviction, isTrue);

    await gesture.up();
    await tester.pump();
    expect(session.buffer.holdEviction, isFalse);
  });
}
