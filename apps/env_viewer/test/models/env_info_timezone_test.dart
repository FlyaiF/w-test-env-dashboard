import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:env_viewer/models/env_info.dart';

/// Simulates the Go sidecar JSON → Flutter display pipeline.
///
/// The Go sidecar reads Oracle DATE (no timezone) as local time, then
/// serializes to RFC 3339 with offset (e.g. "2026-04-10T02:55:00Z").
/// Flutter must parse this as UTC and convert to local before display,
/// otherwise the time will be off by the local UTC offset.
void main() {
  final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  final localOffset = DateTime.now().timeZoneOffset;

  group('updatetime timezone handling', () {
    test('fromJson parses UTC timestamp and preserves UTC', () {
      // Go sidecar sends RFC 3339 UTC time.
      final json = {
        'e_no': 1,
        'e_name': 'test-env',
        'e_updatetime': '2026-04-10T02:55:00Z',
      };

      final env = EnvInfo.fromJson(json);

      expect(env.eUpdatetime, isNotNull);
      expect(env.eUpdatetime!.isUtc, isTrue);
      expect(env.eUpdatetime!.hour, 2);
      expect(env.eUpdatetime!.minute, 55);
    });

    test('toLocal() shifts UTC time to local timezone for display', () {
      final utcTime = DateTime.utc(2026, 4, 10, 2, 55);
      final localTime = utcTime.toLocal();

      // The local time should differ from UTC by the local offset.
      expect(
        localTime.difference(utcTime),
        equals(Duration.zero), // same instant, different representation
      );
      expect(localTime.isUtc, isFalse);
      expect(
        localTime.hour,
        (2 + localOffset.inHours) % 24,
      );
    });

    test('display format uses local time, not raw UTC', () {
      // Simulate the full pipeline:
      // Oracle has 10:55 CST → Go sends 02:55Z → Flutter parses → displays.
      final json = {
        'e_no': 1,
        'e_updatetime': '2026-04-10T02:55:00Z',
      };
      final env = EnvInfo.fromJson(json);

      // BUG (before fix): formatting UTC directly shows 02:55.
      final buggyDisplay = dateFmt.format(env.eUpdatetime!);
      expect(buggyDisplay, contains('02:55'));

      // FIX: formatting with toLocal() shows correct local time.
      final correctDisplay = dateFmt.format(env.eUpdatetime!.toLocal());
      final expectedHour = (2 + localOffset.inHours) % 24;
      final expectedMinute = '55';
      expect(
        correctDisplay,
        contains(
          '${expectedHour.toString().padLeft(2, '0')}:$expectedMinute',
        ),
      );
    });

    test('fromJson with offset timestamp parses correctly', () {
      // Go might also send with explicit offset.
      final json = {
        'e_no': 2,
        'e_updatetime': '2026-04-10T10:55:00+08:00',
      };

      final env = EnvInfo.fromJson(json);

      expect(env.eUpdatetime, isNotNull);
      // Dart parses +08:00 as UTC equivalent: 02:55 UTC.
      expect(env.eUpdatetime!.isUtc, isTrue);
      expect(env.eUpdatetime!.hour, 2);
      expect(env.eUpdatetime!.minute, 55);

      // Display in local should match the original 10:55 for CST machines.
      final localTime = env.eUpdatetime!.toLocal();
      final expectedHour = (2 + localOffset.inHours) % 24;
      expect(localTime.hour, expectedHour);
    });

    test('null updatetime is handled gracefully', () {
      final json = {
        'e_no': 3,
        'e_updatetime': null,
      };

      final env = EnvInfo.fromJson(json);
      expect(env.eUpdatetime, isNull);
    });
  });
}
