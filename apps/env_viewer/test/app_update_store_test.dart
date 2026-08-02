import 'package:env_viewer/services/update/app_update_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateStore.isNewerVersion', () {
    test('orders numerically, not lexically', () {
      expect(AppUpdateStore.isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(AppUpdateStore.isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(AppUpdateStore.isNewerVersion('1.2.1', '1.2.0'), isTrue);
    });

    test('equal or older versions never trigger an offer', () {
      expect(AppUpdateStore.isNewerVersion('1.2.0', '1.2.0'), isFalse);
      expect(AppUpdateStore.isNewerVersion('1.1.9', '1.2.0'), isFalse);
      expect(AppUpdateStore.isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('malformed segments compare as zero and never win', () {
      expect(AppUpdateStore.isNewerVersion('abc', '1.0.0'), isFalse);
      expect(AppUpdateStore.isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(AppUpdateStore.isNewerVersion('1.0.1', '1.0'), isTrue);
    });
  });
}
