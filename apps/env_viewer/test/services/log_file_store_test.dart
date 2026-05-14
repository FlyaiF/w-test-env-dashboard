import 'dart:io';
import 'package:test/test.dart';
import 'package:env_viewer/services/log_file_store.dart';

void main() {
  group('LogFileStore', () {
    late LogFileStore store;

    setUp(() async {
      store = await LogFileStore.create();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('starts with zero lines', () {
      expect(store.totalLines, 0);
    });

    test('appendLine increments totalLines', () {
      store.appendLine('line 1');
      store.appendLine('line 2');
      store.appendLine('line 3');
      expect(store.totalLines, 3);
    });

    test('readLines returns appended lines', () async {
      store.appendLine('aaa');
      store.appendLine('bbb');
      store.appendLine('ccc');

      final lines = await store.readLines(0, 3);
      expect(lines, ['aaa', 'bbb', 'ccc']);
    });

    test('readLines returns a subrange', () async {
      for (var i = 0; i < 10; i++) {
        store.appendLine('line $i');
      }

      final lines = await store.readLines(3, 6);
      expect(lines, ['line 3', 'line 4', 'line 5']);
    });

    test('readLines clamps out-of-bounds range', () async {
      store.appendLine('only');

      final lines = await store.readLines(-5, 100);
      expect(lines, ['only']);
    });

    test('readLines returns empty for empty range', () async {
      store.appendLine('x');
      expect(await store.readLines(0, 0), isEmpty);
      expect(await store.readLines(5, 5), isEmpty);
    });

    test('readAllText returns full content', () async {
      store.appendLine('hello');
      store.appendLine('world');

      final text = await store.readAllText();
      expect(text, 'hello\nworld\n');
    });

    test('handles UTF-8 characters', () async {
      store.appendLine('日志信息: 测试环境');
      store.appendLine('エラー: 接続失敗');

      final lines = await store.readLines(0, 2);
      expect(lines[0], '日志信息: 测试环境');
      expect(lines[1], 'エラー: 接続失敗');
    });

    test('handles large number of lines', () async {
      const count = 5000;
      for (var i = 0; i < count; i++) {
        store.appendLine('line $i');
      }
      expect(store.totalLines, count);

      final first10 = await store.readLines(0, 10);
      expect(first10.first, 'line 0');
      expect(first10.last, 'line 9');

      final last10 = await store.readLines(count - 10, count);
      expect(last10.first, 'line ${count - 10}');
      expect(last10.last, 'line ${count - 1}');

      final mid = await store.readLines(2500, 2503);
      expect(mid, ['line 2500', 'line 2501', 'line 2502']);
    });

    test('dispose deletes the temp file', () async {
      store.appendLine('data');
      final text = await store.readAllText();
      expect(text.isNotEmpty, true);

      await store.dispose();

      // After dispose, reads return empty
      expect(await store.readAllText(), '');
      expect(await store.readLines(0, 1), isEmpty);
    });

    test('multiple stores are independent', () async {
      final store2 = await LogFileStore.create();

      store.appendLine('store1');
      store2.appendLine('store2');

      expect(await store.readLines(0, 1), ['store1']);
      expect(await store2.readLines(0, 1), ['store2']);

      await store2.dispose();
    });

    test('cleanOrphans removes ssh_log temp files', () async {
      // Create a few orphan files manually
      final dir = Directory.systemTemp;
      final orphan1 = File('${dir.path}/ssh_log_orphan_1.tmp');
      final orphan2 = File('${dir.path}/ssh_log_orphan_2.tmp');
      await orphan1.writeAsString('orphan');
      await orphan2.writeAsString('orphan');

      await LogFileStore.cleanOrphans();

      expect(await orphan1.exists(), false);
      expect(await orphan2.exists(), false);
    });
  });
}
