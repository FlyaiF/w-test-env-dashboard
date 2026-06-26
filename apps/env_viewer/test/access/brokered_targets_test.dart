import 'package:env_viewer/api/dto/database_credential.dart';
import 'package:env_viewer/api/dto/server_credential.dart';
import 'package:env_viewer/services/access/brokered_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sshTargetFromServer', () {
    test('carries the brokered secret into the SSH target', () {
      final target = sshTargetFromServer(
        const ServerCredential(
          serverId: 1,
          host: '10.0.0.1',
          port: 2222,
          username: 'deploy',
          secret: 'pw',
        ),
        startPath: '/var/log',
      );

      expect(target.host, '10.0.0.1');
      expect(target.port, 2222);
      expect(target.username, 'deploy');
      expect(target.password, 'pw');
      expect(target.startPath, '/var/log');
    });

    test('defaults to port 22 when the server has no ssh port', () {
      final target = sshTargetFromServer(
        const ServerCredential(serverId: 1, host: 'h', username: 'u'),
      );
      expect(target.port, 22);
      expect(target.password, isNull);
    });
  });

  group('dbTargetFromDatabase', () {
    test('maps connection fields and the brokered secret', () {
      final target = dbTargetFromDatabase(
        const DatabaseCredential(
          databaseId: 9,
          type: 'ORACLE',
          host: '10.0.2.5',
          port: 1521,
          serviceName: 'ORCL',
          username: 'app',
          jdbcUrl: 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL',
          secret: 'db-pw',
        ),
        name: 'biz',
      );

      expect(target.type, 'ORACLE');
      expect(target.host, '10.0.2.5');
      expect(target.port, 1521);
      expect(target.database, 'ORCL');
      expect(target.username, 'app');
      expect(target.jdbcUrl, 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL');
      expect(target.password, 'db-pw');
      expect(target.name, 'biz');
    });
  });
}
