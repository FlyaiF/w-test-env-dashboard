import 'package:env_viewer/api/dto/database_dto.dart';
import 'package:env_viewer/api/dto/server_dto.dart';
import 'package:env_viewer/inventory/inventory_acl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InventoryAcl Server mapping', () {
    test('maps non-secret coordinates and localized labels', () {
      final view = InventoryAcl.toServerView(
        const ServerDto(
          id: 7,
          host: '  app-01  ',
          os: 'LINUX',
          ssh: SshAccessInfo(
            host: '  ssh-01  ',
            port: 2222,
            username: '  deploy  ',
          ),
        ),
      );

      expect(view.id, 7);
      expect(view.host, 'app-01');
      expect(view.os, 'LINUX');
      expect(view.osLabel, 'Linux');
      expect(view.sshHost, 'ssh-01');
      expect(view.sshPort, 2222);
      expect(view.sshUsername, 'deploy');
      expect(view.displayLabel, 'app-01');
      expect(view.displayLabel, 'app-01');
      expect(view.sshAddress, 'deploy@ssh-01:2222');
    });

    test('normalizes blank hosts and SSH address fallbacks', () {
      final blank = InventoryAcl.toServerView(
        const ServerDto(id: 6, host: '  '),
      );
      final defaultPort = InventoryAcl.toServerView(
        const ServerDto(
          id: 7,
          host: 'app-07',
          ssh: SshAccessInfo(port: 22, username: 'ops'),
        ),
      );

      expect(blank.displayLabel, '#6');
      expect(defaultPort.sshAddress, 'ops@app-07');
    });
  });

  group('InventoryAcl Database mapping', () {
    test('localizes role/type and builds a display address', () {
      final view = InventoryAcl.toDatabaseView(
        const DatabaseDto(
          id: 12,
          role: ' business ',
          type: 'DAMENG',
          connection: ConnectionInfo(
            host: ' db-01 ',
            port: 5236,
            serviceName: ' APP ',
            username: ' app_user ',
          ),
        ),
      );

      expect(view.id, 12);
      expect(view.role, 'business');
      expect(view.roleLabel, '业务库');
      expect(view.type, 'DAMENG');
      expect(view.typeLabel, '达梦');
      expect(view.host, 'db-01');
      expect(view.port, 5236);
      expect(view.serviceName, 'APP');
      expect(view.username, 'app_user');
      expect(view.address, 'db-01:5236/APP');
      expect(view.displayLabel, '业务库 · 达梦 · db-01:5236/APP');
      expect(view.displayLabel, '业务库 · 达梦 · db-01:5236/APP');
      expect(view.menuLabel, '业务库 db-01');
    });

    test('centralizes known, unknown, and blank role/type labels', () {
      expect(InventoryAcl.databaseRoleLabel('intermediate'), '中转库');
      expect(InventoryAcl.databaseRoleLabel('cache'), 'cache');
      expect(InventoryAcl.databaseRoleLabel(null), '未指定');
      expect(InventoryAcl.databaseTypeLabel('ORACLE'), 'Oracle');
      expect(InventoryAcl.databaseTypeLabel('DAMENG'), '达梦');
      expect(InventoryAcl.databaseTypeLabel('OCEANBASE'), 'OceanBase');
      expect(InventoryAcl.databaseTypeLabel('OTHER'), '其他');
    });

    test('address omits missing connection segments', () {
      final noPort = InventoryAcl.toDatabaseView(
        const DatabaseDto(
          id: 1,
          role: 'business',
          type: 'ORACLE',
          connection: ConnectionInfo(host: 'h', serviceName: 'svc'),
        ),
      );
      final noService = InventoryAcl.toDatabaseView(
        const DatabaseDto(
          id: 2,
          role: 'business',
          type: 'ORACLE',
          connection: ConnectionInfo(host: 'h', port: 1521),
        ),
      );

      expect(noPort.address, 'h/svc');
      expect(noService.address, 'h:1521');
    });
  });

  test('inventory lists have deterministic display-label and id ordering', () {
    final servers = InventoryAcl.toServerViews(const [
      ServerDto(id: 8, host: 'node-b'),
      ServerDto(id: 9, host: 'node-a'),
      ServerDto(id: 2, host: 'node-a'),
    ]);
    final databases = InventoryAcl.toDatabaseViews(const [
      DatabaseDto(
        id: 8,
        role: 'business',
        type: 'ORACLE',
        connection: ConnectionInfo(host: 'db-b'),
      ),
      DatabaseDto(
        id: 9,
        role: 'business',
        type: 'ORACLE',
        connection: ConnectionInfo(host: 'db-a'),
      ),
      DatabaseDto(
        id: 2,
        role: 'business',
        type: 'ORACLE',
        connection: ConnectionInfo(host: 'db-a'),
      ),
    ]);

    expect(servers.map((view) => view.id), [2, 9, 8]);
    expect(databases.map((view) => view.id), [2, 9, 8]);
  });
}
