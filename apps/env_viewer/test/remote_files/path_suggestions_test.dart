import 'package:env_viewer/remote_files/path_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const known = [
    '/home/ta66/GTZG/trust-ops/logs/gw.log',
    '/home/ta66/GTZG/trust-ops/logs/app.log',
    '/var/log/nginx/access.log',
  ];

  group('known-path keyword matching', () {
    test('every whitespace token must occur somewhere in the path', () async {
      expect(
        await buildPathSuggestions(input: 'trust log', knownPaths: known),
        ['/home/ta66/GTZG/trust-ops/logs/gw.log',
         '/home/ta66/GTZG/trust-ops/logs/app.log'],
      );
      expect(
        await buildPathSuggestions(input: 'nginx', knownPaths: known),
        ['/var/log/nginx/access.log'],
      );
      expect(
        await buildPathSuggestions(input: 'nginx gtzg', knownPaths: known),
        isEmpty,
      );
    });

    test('matching is case-insensitive', () async {
      expect(
        await buildPathSuggestions(input: 'GTZG', knownPaths: known),
        hasLength(2),
      );
    });

    test('empty input lists all known paths', () async {
      expect(
        await buildPathSuggestions(input: '  ', knownPaths: known),
        known,
      );
    });
  });

  group('remote directory completion', () {
    Future<List<String>> lister(String dir) async {
      expect(dir, '/home/ta66/GTZG/trust-ops/logs/');
      return ['gw.log', 'gw.2026-08-01.log', 'archive/', 'app.log'];
    }

    test('completes the fragment after the last slash, sorted', () async {
      final got = await buildPathSuggestions(
        input: '/home/ta66/GTZG/trust-ops/logs/gw',
        knownPaths: known,
        listDirectory: lister,
      );
      expect(got, [
        '/home/ta66/GTZG/trust-ops/logs/gw.2026-08-01.log',
        '/home/ta66/GTZG/trust-ops/logs/gw.log',
      ]);
    });

    test('a trailing slash lists the whole directory before known matches',
        () async {
      final got = await buildPathSuggestions(
        input: '/home/ta66/GTZG/trust-ops/logs/',
        knownPaths: known,
        listDirectory: lister,
      );
      expect(got.take(4), [
        '/home/ta66/GTZG/trust-ops/logs/app.log',
        '/home/ta66/GTZG/trust-ops/logs/archive/',
        '/home/ta66/GTZG/trust-ops/logs/gw.2026-08-01.log',
        '/home/ta66/GTZG/trust-ops/logs/gw.log',
      ]);
    });

    test('remote and known results deduplicate', () async {
      final got = await buildPathSuggestions(
        input: '/home/ta66/GTZG/trust-ops/logs/gw.log',
        knownPaths: known,
        listDirectory: lister,
      );
      expect(
        got.where((p) => p == '/home/ta66/GTZG/trust-ops/logs/gw.log'),
        hasLength(1),
      );
    });

    test('without a lister only keyword matches surface', () async {
      final got = await buildPathSuggestions(
        input: '/home/ta66/GTZG/trust-ops/logs/gw',
        knownPaths: known,
      );
      expect(got, ['/home/ta66/GTZG/trust-ops/logs/gw.log']);
    });

    test('the result set is capped', () async {
      final got = await buildPathSuggestions(
        input: '/logs/',
        knownPaths: const [],
        listDirectory: (_) async =>
            List.generate(50, (i) => 'file$i.log'),
        limit: 12,
      );
      expect(got, hasLength(12));
    });
  });
}
