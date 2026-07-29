import 'package:env_viewer/api/dto/component_dto.dart';
import 'package:env_viewer/api/dto/environment_dto.dart';
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

  group('EnvironmentHealth rollup', () {
    final now = DateTime.utc(2026, 7, 29, 12);

    ComponentDto comp(
      int id, {
      String? status,
      DateTime? collectedAt,
      String? detail,
    }) {
      return ComponentDto(
        id: id,
        role: 'APP',
        collectionStatus: status,
        collectionDetail: detail,
        lastCollectedAt: collectedAt,
      );
    }

    EnvironmentView view(List<ComponentDto> components) => CatalogAcl.toView(
      EnvironmentDto(id: 1, name: 'E', components: components),
      now: now,
    );

    test('any FAILED component makes the environment 异常', () {
      final health = view([
        comp(1, status: 'OK', collectedAt: now),
        comp(2, status: 'FAILED', collectedAt: now),
      ]).health;
      expect(health.state, EnvironmentHealthState.failed);
    });

    test('no failure but an uncollected component means 待采集', () {
      final health = view([
        comp(1, status: 'OK', collectedAt: now),
        comp(2, status: null),
      ]).health;
      expect(health.state, EnvironmentHealthState.pending);
    });

    test('all collectable components OK means 正常', () {
      final health = view([
        comp(1, status: 'OK', collectedAt: now),
        comp(2, status: 'OK', collectedAt: now),
      ]).health;
      expect(health.state, EnvironmentHealthState.ok);
      expect(health.isStale, isFalse);
    });

    test('UNSUPPORTED components are excluded from the rollup', () {
      final health = view([
        comp(1, status: 'OK', collectedAt: now),
        comp(2, status: 'UNSUPPORTED'),
      ]).health;
      expect(health.state, EnvironmentHealthState.ok);
    });

    test('an environment with only UNSUPPORTED (or no) components is 正常', () {
      expect(
        view([comp(1, status: 'UNSUPPORTED')]).health.state,
        EnvironmentHealthState.ok,
      );
      expect(view([]).health.state, EnvironmentHealthState.ok);
      expect(view([]).health.newestCollectedAt, isNull);
      expect(view([]).health.isStale, isFalse);
    });

    test('stale when the newest collection is older than 24h', () {
      final old = now.subtract(const Duration(hours: 25));
      final health = view([comp(1, status: 'OK', collectedAt: old)]).health;
      expect(health.newestCollectedAt, old);
      expect(health.isStale, isTrue);
    });

    test('fresh within 24h, and the newest collectable timestamp wins', () {
      final old = now.subtract(const Duration(hours: 30));
      final fresh = now.subtract(const Duration(hours: 2));
      final health = view([
        comp(1, status: 'OK', collectedAt: old),
        comp(2, status: 'FAILED', collectedAt: fresh),
      ]).health;
      expect(health.newestCollectedAt, fresh);
      expect(health.isStale, isFalse);
    });

    test('UNSUPPORTED timestamps do not count toward freshness', () {
      final old = now.subtract(const Duration(hours: 30));
      final fresh = now.subtract(const Duration(hours: 1));
      final health = view([
        comp(1, status: 'OK', collectedAt: old),
        comp(2, status: 'UNSUPPORTED', collectedAt: fresh),
      ]).health;
      expect(health.newestCollectedAt, old);
      expect(health.isStale, isTrue);
    });

    test('never-collected environments are not flagged stale', () {
      final health = view([comp(1, status: null)]).health;
      expect(health.newestCollectedAt, isNull);
      expect(health.isStale, isFalse);
    });

    test('collectionDetail is mapped onto the component view', () {
      final c = view([
        comp(1, status: 'FAILED', detail: 'connection refused'),
      ]).components.single;
      expect(c.collectionDetail, 'connection refused');
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

  group('CatalogAcl.sqlplusConnectString', () {
    test('full form is username/password@host:port/serviceName', () {
      expect(
        CatalogAcl.sqlplusConnectString(
          username: 'app',
          password: 'pw',
          host: 'h',
          port: 1521,
          serviceName: 'ORCL',
        ),
        'app/pw@h:1521/ORCL',
      );
    });

    test('omits the password segment when none is brokered', () {
      expect(
        CatalogAcl.sqlplusConnectString(
          username: 'app',
          host: 'h',
          port: 1521,
          serviceName: 'ORCL',
        ),
        'app@h:1521/ORCL',
      );
    });

    test('omits the whole credential prefix when there is no username', () {
      expect(
        CatalogAcl.sqlplusConnectString(
          host: 'h',
          port: 1521,
          serviceName: 'ORCL',
        ),
        'h:1521/ORCL',
      );
    });

    test('omits a missing port or service, and is empty without a host', () {
      expect(
        CatalogAcl.sqlplusConnectString(
          username: 'app',
          password: 'pw',
          host: 'h',
          serviceName: 'ORCL',
        ),
        'app/pw@h/ORCL',
      );
      expect(
        CatalogAcl.sqlplusConnectString(username: 'app', password: 'pw'),
        '',
      );
    });
  });
}
