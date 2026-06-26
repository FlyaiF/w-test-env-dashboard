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

    test('version probe and collection status map across all enum values', () {
      expect(CatalogAcl.versionProbeLabel('DB'), '数据库查询');
      expect(CatalogAcl.versionProbeLabel('SSH_FILE'), 'SSH 文件');
      expect(CatalogAcl.versionProbeLabel('COMMAND'), '命令');
      expect(CatalogAcl.versionProbeLabel('NONE'), '无');

      expect(CatalogAcl.collectionStatusLabel('FAILED'), '失败');
      expect(CatalogAcl.collectionStatusLabel('UNSUPPORTED'), '不支持');
    });
  });
}
