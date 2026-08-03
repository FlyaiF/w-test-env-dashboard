import 'package:env_viewer/services/db_tools/db_tool.dart';
import 'package:env_viewer/services/db_tools/tools/plsqldev_connection.dart';
import 'package:env_viewer/services/db_tools/tools/plsqldev_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildPlsqldevUserid', () {
    test('builds the full EZConnect logon from discrete fields', () {
      final userid = buildPlsqldevUserid(
        const DbConnectionTarget(
          type: 'ORACLE',
          host: '10.20.154.151',
          port: 1521,
          database: 'orcl',
          username: 'bjfz',
          password: 's3cret',
        ),
      );
      expect(userid, 'bjfz/s3cret@10.20.154.151:1521/orcl');
    });

    test('omits the password so PL/SQL Developer prompts instead of failing', () {
      final userid = buildPlsqldevUserid(
        const DbConnectionTarget(
          host: 'db.example',
          port: 1521,
          database: 'ORCL',
          username: 'app',
        ),
      );
      expect(userid, 'app@db.example:1521/ORCL');
    });

    test('omits port and service segments when unknown', () {
      final userid = buildPlsqldevUserid(
        const DbConnectionTarget(host: 'db.example', username: 'app'),
      );
      expect(userid, 'app@db.example');
    });

    test('returns null without a host or username', () {
      expect(
        buildPlsqldevUserid(const DbConnectionTarget(username: 'app')),
        isNull,
      );
      expect(
        buildPlsqldevUserid(const DbConnectionTarget(host: 'db.example')),
        isNull,
      );
    });
  });

  group('PlsqldevTool', () {
    test('supports only Oracle databases', () {
      final tool = PlsqldevTool();
      expect(tool.supportsType('ORACLE'), isTrue);
      expect(tool.supportsType('DAMENG'), isFalse);
      expect(tool.supportsType('OCEANBASE'), isFalse);
      expect(tool.supportsType(null), isFalse);
    });
  });
}
