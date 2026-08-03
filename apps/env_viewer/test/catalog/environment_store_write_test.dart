import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/component_links_input.dart';
import 'package:env_viewer/api/dto/component_input.dart';
import 'package:env_viewer/api/dto/environment_input.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('EnvironmentStore curation', () {
    test(
      'createEnvironment writes then re-fetches the canonical list',
      () async {
        var posts = 0;
        final store = EnvironmentStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((req) async {
              if (req.method == 'POST') {
                posts++;
                return http.Response(
                  jsonEncode({'id': 1, 'name': 'ENV-A', 'components': []}),
                  201,
                );
              }
              return http.Response(
                jsonEncode([
                  {'id': 1, 'name': 'ENV-A', 'memo': null, 'components': []},
                ]),
                200,
              );
            }),
          ),
        );

        final ok = await store.createEnvironment(
          const EnvironmentInput(name: 'ENV-A'),
        );

        expect(ok, isTrue);
        expect(posts, 1);
        expect(store.error, isNull);
        expect(store.environments.map((e) => e.name), ['ENV-A']);
      },
    );

    test('addComponent posts to the nested endpoint and reloads', () async {
      Uri? posted;
      final store = EnvironmentStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((req) async {
            if (req.method == 'POST') {
              posted = req.url;
              return http.Response(jsonEncode({'id': 10, 'role': 'UI'}), 201);
            }
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'ENV-A',
                  'components': [
                    {'id': 10, 'role': 'UI'},
                  ],
                },
              ]),
              200,
            );
          }),
        ),
      );

      final ok = await store.addComponent(1, const ComponentInput(role: 'UI'));

      expect(ok, isTrue);
      expect(posted?.path, '/api/environments/1/components');
      expect(store.environments.single.components.single.roleLabel, '界面');
    });

    test(
      'a failed mutation captures the localized error and returns false',
      () async {
        final store = EnvironmentStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((req) async {
              if (req.method == 'DELETE') {
                return http.Response('conflict', 409);
              }
              return http.Response('[]', 200);
            }),
          ),
        );

        final ok = await store.deleteEnvironment(5);

        expect(ok, isFalse);
        expect(store.error, contains('409'));
      },
    );

    test(
      'replacing Component links reloads the canonical Environment',
      () async {
        Map<String, dynamic>? submitted;
        final store = EnvironmentStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((req) async {
              if (req.method == 'PUT' &&
                  req.url.path == '/api/components/10/links') {
                submitted = jsonDecode(req.body) as Map<String, dynamic>;
                return http.Response(
                  jsonEncode({
                    'id': 10,
                    'role': 'UI',
                    'serverId': 2,
                    'databaseIds': [3, 4],
                  }),
                  200,
                );
              }
              if (req.url.path == '/api/environments') {
                return http.Response(
                  jsonEncode([
                    {
                      'id': 1,
                      'name': 'ENV-A',
                      'components': [
                        {
                          'id': 10,
                          'role': 'UI',
                          'serverId': 2,
                          'databaseIds': [3, 4],
                        },
                      ],
                    },
                  ]),
                  200,
                );
              }
              return http.Response('[]', 200);
            }),
          ),
        );

        final ok = await store.setComponentLinks(
          10,
          const ComponentLinksInput(serverId: 2, databaseIds: [3, 4]),
        );

        expect(ok, isTrue);
        expect(submitted, {
          'serverId': 2,
          'databaseIds': [3, 4],
        });
        final component = store.environments.single.components.single;
        expect(component.serverId, 2);
        expect(component.databaseIds, [3, 4]);
      },
    );

    test(
      'a failed canonical reload makes a successful link write fail',
      () async {
        final store = EnvironmentStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((request) async {
              if (request.method == 'PUT') {
                return http.Response(
                  jsonEncode({
                    'id': 10,
                    'role': 'APP',
                    'serverId': 2,
                    'databaseIds': [3],
                  }),
                  200,
                );
              }
              return http.Response(
                jsonEncode({'detail': '目录刷新失败'}),
                503,
                headers: {'content-type': 'application/problem+json'},
              );
            }),
          ),
        );

        final ok = await store.setComponentLinks(
          10,
          const ComponentLinksInput(serverId: 2, databaseIds: [3]),
        );

        expect(ok, isFalse);
        expect(store.error, contains('目录刷新失败'));
      },
    );
  });
}
