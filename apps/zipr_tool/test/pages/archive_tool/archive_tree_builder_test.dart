import 'package:flutter_test/flutter_test.dart';
import 'package:zipr_tool/pages/archive_tool/archive_tree_builder.dart';
import 'package:zipr_tool/src/rust/api/zipr_api.dart';

ArchiveEntry _entry(String expr, {int size = 100, int compressed = 50}) {
  return ArchiveEntry(
    expr: expr,
    size: BigInt.from(size),
    compressedSize: BigInt.from(compressed),
  );
}

void main() {
  group('ArchiveTreeBuilder', () {
    test('empty list returns empty tree', () {
      final tree = buildTree([]);
      expect(tree, isEmpty);
    });

    test('flat archive: all entries at root level', () {
      final entries = [
        _entry('test.zip!/README.md'),
        _entry('test.zip!/main.txt'),
      ];

      final tree = buildTree(entries);
      expect(tree.length, 1); // test.zip root
      final zip = tree[0];
      expect(zip.name, 'test.zip');
      expect(zip.children.length, 2);
      expect(zip.children[0].name, 'main.txt');
      expect(zip.children[1].name, 'README.md');
    });

    test('directory grouping: entries share a common parent', () {
      final entries = [
        _entry('test.zip!/src/main.rs'),
        _entry('test.zip!/src/lib.rs'),
        _entry('test.zip!/Cargo.toml'),
      ];

      final tree = buildTree(entries);
      final zip = tree[0];
      // Directories first, then files
      final srcNode = zip.children.firstWhere((n) => n.name == 'src');
      expect(srcNode.children.length, 2);
      expect(zip.children.any((n) => n.name == 'Cargo.toml'), true);
    });

    test('nested jar: entries grouped under archive nodes', () {
      final entries = [
        _entry('app.jar!/META-INF/MANIFEST.MF'),
        _entry('app.jar!/com/example/Main.class'),
      ];

      final tree = buildTree(entries);
      expect(tree.length, 1);

      final appJar = tree[0];
      expect(appJar.name, 'app.jar');
      expect(appJar.isArchive, true);
      expect(appJar.children.length, 2); // META-INF and com
    });

    test('deeply nested: 3-level nesting via !/ separator', () {
      final entries = [
        _entry('outer.jar!/BOOT-INF/lib/inner.jar!/com/Foo.class'),
      ];

      final tree = buildTree(entries);
      expect(tree.length, 1);

      final outer = tree[0];
      expect(outer.name, 'outer.jar');
      expect(outer.isArchive, true);

      final bootInf = outer.children[0];
      expect(bootInf.name, 'BOOT-INF');

      final lib = bootInf.children[0];
      expect(lib.name, 'lib');

      final inner = lib.children[0];
      expect(inner.name, 'inner.jar');
      expect(inner.isArchive, true);

      final com = inner.children[0];
      expect(com.name, 'com');

      final foo = com.children[0];
      expect(foo.name, 'Foo.class');
      expect(foo.isLeaf, true);
      expect(foo.entry, isNotNull);
    });

    test('entries sorted: directories before files', () {
      final entries = [
        _entry('test.zip!/b.txt'),
        _entry('test.zip!/a/file.txt'),
        _entry('test.zip!/c.txt'),
      ];

      final tree = buildTree(entries);
      final zip = tree[0];
      // 'a' directory should come first
      expect(zip.children[0].name, 'a');
      expect(zip.children[1].name, 'b.txt');
      expect(zip.children[2].name, 'c.txt');
    });

    test('duplicate prefixes merged into single parent node', () {
      final entries = [
        _entry('test.zip!/lib/foo.dart'),
        _entry('test.zip!/lib/bar.dart'),
        _entry('test.zip!/lib/src/baz.dart'),
      ];

      final tree = buildTree(entries);
      final zip = tree[0];
      expect(zip.children.length, 1); // single 'lib' node
      final lib = zip.children[0];
      expect(lib.name, 'lib');
      // children: src (dir), bar.dart, foo.dart
      expect(lib.children.length, 3);
    });

    test('archive extensions detected correctly', () {
      final entries = [
        _entry('app.war!/WEB-INF/web.xml'),
        _entry('bundle.ear!/app.jar!/Main.class'),
      ];

      final tree = buildTree(entries);
      final war = tree.firstWhere((n) => n.name == 'app.war');
      expect(war.isArchive, true);

      final ear = tree.firstWhere((n) => n.name == 'bundle.ear');
      expect(ear.isArchive, true);
      final innerJar = ear.children[0];
      expect(innerJar.name, 'app.jar');
      expect(innerJar.isArchive, true);
    });
  });
}
