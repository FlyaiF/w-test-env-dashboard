import 'package:env_viewer/api/dto/component_dto.dart';
import 'package:env_viewer/api/dto/database_dto.dart';
import 'package:env_viewer/api/dto/environment_dto.dart';
import 'package:env_viewer/api/dto/server_dto.dart';
import 'package:env_viewer/catalog/catalog_acl.dart';
import 'package:env_viewer/catalog/environment_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogAcl.toView', () {
    test('maps an environment and its components into view models', () {
      final view = CatalogAcl.toView(
        const EnvironmentDto(
          id: 1,
          name: 'Alpha',
          memo: '  集成环境  ',
          components: [
            ComponentDto(
              id: 10,
              role: 'GATEWAY',
              version: '1.2.3',
              serverId: 100,
              databaseIds: [200, 201],
              versionProbe: 'HTTP',
              collectionStatus: 'OK',
            ),
          ],
        ),
      );

      expect(view.id, 1);
      expect(view.name, 'Alpha');
      expect(view.memo, '集成环境'); // trimmed
      expect(view.componentCount, 1);

      final c = view.components.single;
      expect(c.roleLabel, '网关');
      expect(c.version, '1.2.3');
      expect(c.serverId, 100);
      expect(c.databaseIds, [200, 201]);
      expect(c.versionProbeLabel, 'HTTP 接口');
      expect(c.collectionState, CollectionState.ok);
      expect(c.collectionStatusLabel, '正常');
    });

    test('falls back to a placeholder for an unnamed environment', () {
      final view = CatalogAcl.toView(const EnvironmentDto(id: 2, name: '   '));
      expect(view.name, CatalogAcl.unnamedEnvironment);
    });

    test('blank component strings collapse to null', () {
      final view = CatalogAcl.toView(
        const EnvironmentDto(
          id: 3,
          name: 'Beta',
          components: [
            ComponentDto(id: 11, role: 'UI', version: '   ', url: ''),
          ],
        ),
      );
      final c = view.components.single;
      expect(c.version, isNull);
      expect(c.url, isNull);
    });

    test('null collection status reads as not-collected (pre-slice-05)', () {
      final view = CatalogAcl.toView(
        const EnvironmentDto(
          id: 4,
          name: 'Gamma',
          components: [ComponentDto(id: 12, role: 'APP')],
        ),
      );
      final c = view.components.single;
      expect(c.collectionState, CollectionState.notCollected);
      expect(c.collectionStatusLabel, '未采集');
    });
  });

  group('CatalogAcl label mapping', () {
    test('known roles map to Chinese labels', () {
      expect(CatalogAcl.roleLabel('GATEWAY'), '网关');
      expect(CatalogAcl.roleLabel('UI'), '界面');
      expect(CatalogAcl.roleLabel('APP'), '主服务');
      expect(CatalogAcl.roleLabel('PRIVATE_PROTO'), '专有协议服务');
    });

    test('an unknown role is surfaced verbatim, not dropped', () {
      expect(CatalogAcl.roleLabel('NEW_ROLE'), 'NEW_ROLE');
    });

    test('UNSPECIFIED and the null/blank fallback unify on 未指定', () {
      expect(CatalogAcl.roleLabel('UNSPECIFIED'), '未指定');
      expect(CatalogAcl.roleLabel(null), '未指定');
      expect(CatalogAcl.roleLabel(''), '未指定');
    });

    test('version probe and collection status map across all enum values', () {
      expect(CatalogAcl.versionProbeLabel('DB'), '数据库查询');
      expect(CatalogAcl.versionProbeLabel('SSH_FILE'), 'SSH 文件');
      expect(CatalogAcl.versionProbeLabel('COMMAND'), '命令');
      expect(CatalogAcl.versionProbeLabel('NONE'), '无');

      expect(CatalogAcl.collectionStatusLabel('FAILED'), '失败');
      expect(CatalogAcl.collectionStatusLabel('UNSUPPORTED'), '不支持');
    });
  });

  group('CatalogAcl.serverRefView', () {
    test('uses the host as the card label', () {
      final ref = CatalogAcl.serverRefView(
        const ServerDto(id: 6, host: '10.20.155.175', os: 'LINUX'),
      );
      expect(ref.id, 6);
      expect(ref.cardLabel, '10.20.155.175');
    });

    test('falls back to #id when the host is blank', () {
      final ref = CatalogAcl.serverRefView(const ServerDto(id: 6, host: '  '));
      expect(ref.cardLabel, '#6');
    });
  });

  group('CatalogAcl.databaseRefView', () {
    test('full label is role · type · host:port/service; menu label is role + host', () {
      final ref = CatalogAcl.databaseRefView(
        const DatabaseDto(
          id: 61,
          role: 'business',
          type: 'ORACLE',
          connection: ConnectionInfo(
            host: '10.20.155.175',
            port: 1521,
            serviceName: 'ORCL',
          ),
        ),
      );
      expect(ref.cardLabel, '业务库 · Oracle · 10.20.155.175:1521/ORCL');
      expect(ref.menuLabel, '业务库 10.20.155.175');
    });

    test('intermediate role and type labels map, unknown role passes through', () {
      expect(CatalogAcl.databaseRoleLabel('intermediate'), '中转库');
      expect(CatalogAcl.databaseRoleLabel('cache'), 'cache');
      expect(CatalogAcl.databaseTypeLabel('DAMENG'), '达梦');
      expect(CatalogAcl.databaseTypeLabel('OCEANBASE'), 'OceanBase');
    });

    test('blank segments are dropped from the card label', () {
      final ref = CatalogAcl.databaseRefView(
        const DatabaseDto(id: 9, role: 'business', type: null, connection: null),
      );
      expect(ref.cardLabel, '业务库'); // no type, no address
      expect(ref.menuLabel, '业务库'); // no host
    });

    test('address omits a missing port or service', () {
      final noPort = CatalogAcl.databaseRefView(
        const DatabaseDto(
          id: 1,
          role: 'business',
          type: 'ORACLE',
          connection: ConnectionInfo(host: 'h', serviceName: 'svc'),
        ),
      );
      expect(noPort.address, 'h/svc');

      final noService = CatalogAcl.databaseRefView(
        const DatabaseDto(
          id: 2,
          role: 'business',
          type: 'ORACLE',
          connection: ConnectionInfo(host: 'h', port: 1521),
        ),
      );
      expect(noService.address, 'h:1521');
    });
  });
}
