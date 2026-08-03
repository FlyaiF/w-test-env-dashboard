import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/component_links_input.dart';
import 'package:env_viewer/api/dto/database_input.dart';
import 'package:env_viewer/api/dto/server_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Resource Inventory inputs', () {
    test('ServerInput serializes non-secret SSH coordinates', () {
      final json = const ServerInput(
        host: 'app01.internal',
        os: 'LINUX',
        ssh: SshAccessInput(
          host: 'ssh-gateway.internal',
          port: 2222,
          username: 'deploy',
        ),
      ).toJson();

      expect(json, {
        'host': 'app01.internal',
        'os': 'LINUX',
        'ssh': {
          'host': 'ssh-gateway.internal',
          'port': 2222,
          'username': 'deploy',
        },
      });
    });

    test('DatabaseInput serializes non-secret connection coordinates', () {
      final json = const DatabaseInput(
        role: 'business',
        type: 'ORACLE',
        connection: DatabaseConnectionInput(
          host: 'db01.internal',
          port: 1521,
          serviceName: 'ORCL',
          username: 'app_user',
        ),
      ).toJson();

      expect(json, {
        'role': 'business',
        'type': 'ORACLE',
        'connection': {
          'host': 'db01.internal',
          'port': 1521,
          'serviceName': 'ORCL',
          'username': 'app_user',
        },
      });
    });

    test('ComponentLinksInput serializes replacement link IDs', () {
      final json = const ComponentLinksInput(
        serverId: 12,
        databaseIds: [31, 32],
      ).toJson();

      expect(json, {
        'serverId': 12,
        'databaseIds': [31, 32],
      });
    });
  });

  group('BackendClient Resource Inventory', () {
    test(
      'createServer POSTs the input and parses the created Server',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({
                'id': 12,
                'host': 'app01.internal',
                'os': 'LINUX',
                'ssh': null,
              }),
              201,
            );
          }),
        );

        final server = await client.createServer(
          const ServerInput(host: 'app01.internal', os: 'LINUX'),
        );

        expect(captured.method, 'POST');
        expect(captured.url.path, '/api/servers');
        expect(jsonDecode(captured.body), {
          'host': 'app01.internal',
          'os': 'LINUX',
          'ssh': null,
        });
        expect(server.id, 12);
        expect(server.host, 'app01.internal');
      },
    );

    test('updateServer PUTs the replacement to the Server id path', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'id': 12, 'host': 'app02.internal', 'os': 'WINDOWS'}),
            200,
          );
        }),
      );

      final server = await client.updateServer(
        12,
        const ServerInput(host: 'app02.internal', os: 'WINDOWS'),
      );

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/api/servers/12');
      expect(server.host, 'app02.internal');
      expect(server.os, 'WINDOWS');
    });

    test('deleteServer DELETEs the Server id and accepts no content', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );

      await client.deleteServer(12);

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/api/servers/12');
    });

    test(
      'createDatabase POSTs the input and parses the created Database',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({
                'id': 31,
                'role': 'business',
                'type': 'ORACLE',
                'connection': {'host': 'db01.internal', 'port': 1521},
              }),
              201,
            );
          }),
        );

        final database = await client.createDatabase(
          const DatabaseInput(
            role: 'business',
            type: 'ORACLE',
            connection: DatabaseConnectionInput(
              host: 'db01.internal',
              port: 1521,
            ),
          ),
        );

        expect(captured.method, 'POST');
        expect(captured.url.path, '/api/databases');
        expect(
          (jsonDecode(captured.body)['connection'])['host'],
          'db01.internal',
        );
        expect(database.id, 31);
        expect(database.type, 'ORACLE');
      },
    );

    test(
      'updateDatabase PUTs the replacement to the Database id path',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({'id': 31, 'role': 'reporting', 'type': 'DAMENG'}),
              200,
            );
          }),
        );

        final database = await client.updateDatabase(
          31,
          const DatabaseInput(role: 'reporting', type: 'DAMENG'),
        );

        expect(captured.method, 'PUT');
        expect(captured.url.path, '/api/databases/31');
        expect(database.role, 'reporting');
        expect(database.type, 'DAMENG');
      },
    );

    test(
      'deleteDatabase DELETEs the Database id and accepts no content',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response('', 204);
          }),
        );

        await client.deleteDatabase(31);

        expect(captured.method, 'DELETE');
        expect(captured.url.path, '/api/databases/31');
      },
    );

    test('environmentsOnServer GETs and parses reverse references', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'id': 7,
                  'name': '环境 A',
                  'components': [
                    {'id': 19, 'role': 'APP', 'serverId': 12},
                  ],
                },
              ]),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final environments = await client.environmentsOnServer(12);

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/servers/12/environments');
      expect(environments.single.name, '环境 A');
      expect(environments.single.components.single.serverId, 12);
    });

    test(
      'environmentsUsingDatabase GETs and parses reverse references',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode([
                {
                  'id': 8,
                  'name': 'ENV-B',
                  'components': [
                    {
                      'id': 20,
                      'role': 'PRIVATE_PROTO',
                      'databaseIds': [31],
                    },
                  ],
                },
              ]),
              200,
            );
          }),
        );

        final environments = await client.environmentsUsingDatabase(31);

        expect(captured.method, 'GET');
        expect(captured.url.path, '/api/databases/31/environments');
        expect(environments.single.id, 8);
        expect(environments.single.components.single.databaseIds, [31]);
      },
    );

    test(
      'setComponentLinks PUTs replacement links and parses Component',
      () async {
        late http.Request captured;
        final client = BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({
                'id': 19,
                'role': 'APP',
                'serverId': 12,
                'databaseIds': [31, 32],
              }),
              200,
            );
          }),
        );

        final component = await client.setComponentLinks(
          19,
          const ComponentLinksInput(serverId: 12, databaseIds: [31, 32]),
        );

        expect(captured.method, 'PUT');
        expect(captured.url.path, '/api/components/19/links');
        expect(jsonDecode(captured.body), {
          'serverId': 12,
          'databaseIds': [31, 32],
        });
        expect(component.serverId, 12);
        expect(component.databaseIds, [31, 32]);
      },
    );
  });
}
