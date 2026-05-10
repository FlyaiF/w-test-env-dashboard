import 'package:flutter_test/flutter_test.dart';
import 'package:test_env_dashboard/services/ssh_tools/ssh_tool.dart';
import 'package:test_env_dashboard/services/ssh_tools/tools/netsarang_url.dart';

void main() {
  group('buildNetsarangUrl', () {
    test('encodes reserved characters in password', () {
      final url = buildNetsarangUrl(
        'ssh',
        const ConnectionTarget(
          host: '10.0.0.1',
          port: 2222,
          username: 'root',
          password: 'p@ss:w/d#?&',
        ),
      );
      expect(url, 'ssh://root:p%40ss%3Aw%2Fd%23%3F%26@10.0.0.1:2222');
    });

    test('encodes reserved characters in username', () {
      final url = buildNetsarangUrl(
        'sftp',
        const ConnectionTarget(
          host: 'host.example',
          port: 22,
          username: 'a@b',
          password: 'pw',
        ),
      );
      expect(url, 'sftp://a%40b:pw@host.example:22');
    });

    test('omits user info when username is null', () {
      final url = buildNetsarangUrl(
        'ssh',
        const ConnectionTarget(host: '1.2.3.4', port: 22),
      );
      expect(url, 'ssh://1.2.3.4:22');
    });

    test('omits password when null but keeps username', () {
      final url = buildNetsarangUrl(
        'ssh',
        const ConnectionTarget(
          host: '1.2.3.4',
          port: 22,
          username: 'user',
        ),
      );
      expect(url, 'ssh://user@1.2.3.4:22');
    });

    test('omits password when empty', () {
      final url = buildNetsarangUrl(
        'ssh',
        const ConnectionTarget(
          host: 'h',
          port: 22,
          username: 'u',
          password: '',
        ),
      );
      expect(url, 'ssh://u@h:22');
    });
  });
}
