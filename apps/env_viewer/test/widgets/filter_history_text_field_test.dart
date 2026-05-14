import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _controller = TextEditingController();
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _filterText = _controller.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FilterHistoryTextField(
          controller: _controller,
          filterText: _filterText,
          hintText: '搜索文件...',
        ),
      ),
    );
  }
}

void main() {
  testWidgets('stores a filter term after it remains unchanged for 3 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());

    await tester.enterText(find.byType(TextField), 'stable');
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.history), findsNothing);

    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(PopupMenuItem<String>, 'stable'),
      findsOneWidget,
    );
  });

  testWidgets('resets the store timer when the filter term changes', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());

    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump(const Duration(seconds: 2));
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.history), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(PopupMenuItem<String>, 'second'),
      findsOneWidget,
    );
    expect(find.widgetWithText(PopupMenuItem<String>, 'first'), findsNothing);
  });

  testWidgets('stores the five most recent filter terms', (tester) async {
    await tester.pumpWidget(const _Harness());

    for (final term in ['one', 'two', 'three', 'four', 'five', 'six']) {
      await tester.enterText(find.byType(TextField), term);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
    }

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(PopupMenuItem<String>, 'six'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'five'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'four'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'three'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'two'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<String>, 'one'), findsNothing);
  });

  testWidgets('reapplies a selected history item', (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.enterText(find.byType(TextField), 'Main.class');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main.class').last);
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'Main.class');
  });
}
