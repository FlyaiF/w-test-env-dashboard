import 'package:env_viewer/services/db_tools/db_tool.dart';
import 'package:env_viewer/services/db_tools/tools/dbeaver_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildDbeaverConnectionSpec', () {
    test('prefers the brokered jdbc url when present', () {
      final spec = buildDbeaverConnectionSpec(
        const DbConnectionTarget(
          type: 'ORACLE',
          host: '10.0.2.5',
          port: 1521,
          database: 'ORCL',
          username: 'app',
          password: 'pw',
          jdbcUrl: 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL',
          name: 'biz',
        ),
      );

      expect(
        spec,
        'driver=oracle|url=jdbc:oracle:thin:@//10.0.2.5:1521/ORCL'
        '|user=app|password=pw|name=biz|save=false|connect=true',
      );
    });

    test('falls back to discrete host/port/database without a jdbc url', () {
      final spec = buildDbeaverConnectionSpec(
        const DbConnectionTarget(
          type: 'OTHER',
          host: 'db.host',
          port: 1234,
          database: 'MYDB',
          username: 'u',
          password: 'p',
        ),
      );

      expect(
        spec,
        'driver=generic|host=db.host|port=1234|database=MYDB'
        '|user=u|password=p|save=false|connect=true',
      );
    });

    test('omits an empty password and username', () {
      final spec = buildDbeaverConnectionSpec(
        const DbConnectionTarget(
          type: 'ORACLE',
          jdbcUrl: 'jdbc:oracle:thin:@//h:1521/S',
          username: '',
          password: '',
        ),
      );

      expect(spec, contains('driver=oracle'));
      expect(spec, contains('url=jdbc:oracle:thin:@//h:1521/S'));
      expect(spec, isNot(contains('user=')));
      expect(spec, isNot(contains('password=')));
    });

    test('honors savePassword when explicitly persisting', () {
      final spec = buildDbeaverConnectionSpec(
        const DbConnectionTarget(type: 'OTHER', host: 'h', port: 1),
        savePassword: true,
      );
      expect(spec, contains('save=true'));
    });
  });

  group('dbeaverDriverId', () {
    test('maps Oracle to its built-in driver', () {
      expect(dbeaverDriverId('ORACLE'), 'oracle');
    });

    test('maps home-grown engines to the generic driver', () {
      expect(dbeaverDriverId('DAMENG'), 'generic');
      expect(dbeaverDriverId('OCEANBASE'), 'generic');
      expect(dbeaverDriverId(null), 'generic');
    });
  });
}
