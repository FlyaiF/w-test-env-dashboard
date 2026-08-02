import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'dto/client_update_dto.dart';
import 'dto/component_dto.dart';
import 'dto/component_input.dart';
import 'dto/component_links_input.dart';
import 'dto/database_credential.dart';
import 'dto/database_dto.dart';
import 'dto/database_input.dart';
import 'dto/environment_dto.dart';
import 'dto/environment_input.dart';
import 'dto/server_credential.dart';
import 'dto/server_dto.dart';
import 'dto/server_input.dart';

/// Raised when the backend cannot be reached or returns a non-2xx response.
/// Carries a human-readable, already-localized message for the UI.
class BackendException implements Exception {
  final String message;
  const BackendException(this.message);

  @override
  String toString() => message;
}

/// HTTP client to the backend Environment Catalog API. Reads (slice 01):
/// `GET /api/environments` and `GET /api/environments/{id}`. Curation writes
/// (slice 03): create/update/delete Environments and their nested Components.
/// This is the only way the thin client touches catalog data — there is no
/// local store and no database access. It returns raw DTOs; the anti-corruption
/// layer maps them to view models.
class BackendClient {
  /// Default backend location for local development. Overridable via the
  /// `ENV_DASHBOARD_BACKEND_URL` environment variable or the constructor.
  static const String defaultBaseUrl = 'http://localhost:8080';

  final String baseUrl;
  final http.Client _http;

  BackendClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = _normalize(baseUrl ?? _baseUrlFromEnv()),
      _http = httpClient ?? http.Client();

  static String _baseUrlFromEnv() {
    final fromEnv = Platform.environment['ENV_DASHBOARD_BACKEND_URL'];
    return (fromEnv != null && fromEnv.isNotEmpty) ? fromEnv : defaultBaseUrl;
  }

  static String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Future<List<EnvironmentDto>> listEnvironments() async {
    final body = await _getJson('/api/environments');
    if (body is! List) {
      throw const BackendException('后端返回了无法识别的环境列表');
    }
    return body
        .map((e) => EnvironmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EnvironmentDto> getEnvironment(int id) async {
    final body = await _getJson('/api/environments/$id');
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的环境详情');
    }
    return EnvironmentDto.fromJson(body);
  }

  /// List the shared Servers (Resource Inventory, `GET /api/servers`). Used to
  /// resolve a Component's `serverId` reference to a display label client-side
  /// (ADR-0006) — no secrets are returned.
  Future<List<ServerDto>> listServers() async {
    final body = await _getJson('/api/servers');
    if (body is! List) {
      throw const BackendException('后端返回了无法识别的服务器列表');
    }
    return body
        .map((e) => ServerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a shared Server from non-secret inventory coordinates.
  Future<ServerDto> createServer(ServerInput input) async {
    final body = await _send('POST', '/api/servers', body: input.toJson());
    return _asServer(body);
  }

  /// Replace a shared Server's non-secret inventory coordinates.
  Future<ServerDto> updateServer(int id, ServerInput input) async {
    final body = await _send('PUT', '/api/servers/$id', body: input.toJson());
    return _asServer(body);
  }

  /// Delete an unused shared Server. Referenced Servers fail with backend 409.
  Future<void> deleteServer(int id) async {
    await _send('DELETE', '/api/servers/$id');
  }

  /// Environments containing a Component that runs on this Server.
  Future<List<EnvironmentDto>> environmentsOnServer(int id) async {
    final body = await _getJson('/api/servers/$id/environments');
    return _asEnvironmentList(body);
  }

  /// List the shared Databases (Resource Inventory, `GET /api/databases`). Used to
  /// resolve a Component's `databaseIds` references to display labels client-side
  /// (ADR-0006) — connection metadata only, no passwords.
  Future<List<DatabaseDto>> listDatabases() async {
    final body = await _getJson('/api/databases');
    if (body is! List) {
      throw const BackendException('后端返回了无法识别的数据库列表');
    }
    return body
        .map((e) => DatabaseDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a shared Database from non-secret inventory coordinates.
  Future<DatabaseDto> createDatabase(DatabaseInput input) async {
    final body = await _send('POST', '/api/databases', body: input.toJson());
    return _asDatabase(body);
  }

  /// Replace a shared Database's non-secret inventory coordinates.
  Future<DatabaseDto> updateDatabase(int id, DatabaseInput input) async {
    final body = await _send('PUT', '/api/databases/$id', body: input.toJson());
    return _asDatabase(body);
  }

  /// Delete an unused shared Database. Referenced Databases fail with backend 409.
  Future<void> deleteDatabase(int id) async {
    await _send('DELETE', '/api/databases/$id');
  }

  /// Environments containing a Component that uses this Database.
  Future<List<EnvironmentDto>> environmentsUsingDatabase(int id) async {
    final body = await _getJson('/api/databases/$id/environments');
    return _asEnvironmentList(body);
  }

  /// Ask the backend to collect this Environment right now — 立即采集
  /// (`POST /api/environments/{id}/refresh`, slice 05) — and return its
  /// freshly-collected view (versions, 版本更新时间, per-component status).
  Future<EnvironmentDto> refreshEnvironment(int id) async {
    final body = await _send('POST', '/api/environments/$id/refresh');
    return _asEnvironment(body);
  }

  /// Create an Environment (optionally seeding inline Components) and return it.
  Future<EnvironmentDto> createEnvironment(EnvironmentInput input) async {
    final body = await _send('POST', '/api/environments', body: input.toJson());
    return _asEnvironment(body);
  }

  /// Update an Environment's own fields (name, memo). Components are unaffected.
  Future<EnvironmentDto> updateEnvironment(
    int id,
    EnvironmentInput input,
  ) async {
    final body = await _send(
      'PUT',
      '/api/environments/$id',
      body: input.toJson(),
    );
    return _asEnvironment(body);
  }

  /// Delete an Environment; the backend cascades to its Components only.
  Future<void> deleteEnvironment(int id) async {
    await _send('DELETE', '/api/environments/$id');
  }

  /// Add a Component to an Environment and return it (with its assigned id).
  Future<ComponentDto> addComponent(
    int environmentId,
    ComponentInput input,
  ) async {
    final body = await _send(
      'POST',
      '/api/environments/$environmentId/components',
      body: input.toJson(),
    );
    return _asComponent(body);
  }

  /// Update one Component, scoped to its owning Environment.
  Future<ComponentDto> updateComponent(
    int environmentId,
    int componentId,
    ComponentInput input,
  ) async {
    final body = await _send(
      'PUT',
      '/api/environments/$environmentId/components/$componentId',
      body: input.toJson(),
    );
    return _asComponent(body);
  }

  /// Remove one Component from its owning Environment.
  Future<void> deleteComponent(int environmentId, int componentId) async {
    await _send(
      'DELETE',
      '/api/environments/$environmentId/components/$componentId',
    );
  }

  /// Replace one Component's runs-on Server and uses-Database references.
  Future<ComponentDto> setComponentLinks(
    int componentId,
    ComponentLinksInput input,
  ) async {
    final body = await _send(
      'PUT',
      '/api/components/$componentId/links',
      body: input.toJson(),
    );
    return _asComponent(body);
  }

  /// Store/rotate a Server's SSH secret (`PUT /api/servers/{id}/secret`). The
  /// plaintext is transmitted once and encrypted at rest by the backend; the
  /// client never persists it.
  Future<void> setServerSecret(int serverId, String secret) async {
    await _send(
      'PUT',
      '/api/servers/$serverId/secret',
      body: {'secret': secret},
    );
  }

  /// Store/rotate a Database's login secret (`PUT /api/databases/{id}/secret`).
  /// The plaintext is transmitted once and encrypted at rest by the backend;
  /// the client never persists it.
  Future<void> setDatabaseSecret(int databaseId, String secret) async {
    await _send(
      'PUT',
      '/api/databases/$databaseId/secret',
      body: {'secret': secret},
    );
  }

  /// Fetch an SSH credential bundle for a Server on demand (Access Brokering,
  /// ADR-0005). Returned to the caller to launch a tool with and then dropped;
  /// the client never persists it.
  Future<ServerCredential> getServerCredentials(int serverId) async {
    final body = await _getJson('/api/servers/$serverId/credentials');
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的服务器凭据');
    }
    return ServerCredential.fromJson(body);
  }

  /// Fetch a DB credential bundle for a Database on demand (Access Brokering,
  /// ADR-0005). Used to launch the user's own DB tool; nothing is persisted.
  Future<DatabaseCredential> getDatabaseCredentials(int databaseId) async {
    final body = await _getJson('/api/databases/$databaseId/credentials');
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的数据库凭据');
    }
    return DatabaseCredential.fromJson(body);
  }

  /// The newest published client build for [platform] (`windows`/`macos`), or
  /// null when the backend has updates disabled or nothing published (204).
  Future<ClientUpdateDto?> latestClientUpdate(String platform) async {
    final body = await _getJson(
      '/api/client-updates/env_viewer/latest?platform=$platform',
    );
    if (body == null) return null;
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的更新信息');
    }
    return ClientUpdateDto.fromJson(body);
  }

  /// Streams the exact [version] update zip to [destination]. [onProgress]
  /// reports (receivedBytes, totalBytes); total is -1 when the backend does
  /// not announce a length.
  Future<void> downloadClientUpdate({
    required String platform,
    required String version,
    required File destination,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/client-updates/env_viewer/download'
      '?platform=$platform&version=$version',
    );
    final http.StreamedResponse response;
    try {
      response = await _http.send(http.Request('GET', uri));
    } on SocketException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    } on http.ClientException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException(
        _errorMessage(await http.Response.fromStream(response)),
      );
    }
    final total = response.contentLength ?? -1;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  EnvironmentDto _asEnvironment(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的环境详情');
    }
    return EnvironmentDto.fromJson(body);
  }

  ComponentDto _asComponent(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的组件详情');
    }
    return ComponentDto.fromJson(body);
  }

  ServerDto _asServer(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的服务器详情');
    }
    return ServerDto.fromJson(body);
  }

  DatabaseDto _asDatabase(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw const BackendException('后端返回了无法识别的数据库详情');
    }
    return DatabaseDto.fromJson(body);
  }

  List<EnvironmentDto> _asEnvironmentList(dynamic body) {
    if (body is! List) {
      throw const BackendException('后端返回了无法识别的环境列表');
    }
    return body
        .map((e) => EnvironmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<dynamic> _getJson(String path) => _send('GET', path);

  /// Sends a request and decodes a JSON response. A 2xx with an empty body
  /// (e.g. 204 No Content from a delete) decodes to null. Connection and
  /// non-2xx failures surface as a localized [BackendException].
  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _http.send(request);
      response = await http.Response.fromStream(streamed);
    } on SocketException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    } on http.ClientException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException(_errorMessage(response));
    }
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const BackendException('后端返回了无法解析的数据');
    }
  }

  /// Builds a localized message for a failed request. The backend answers errors
  /// with RFC-7807 `problem+json` (a `detail`/`title` field) — surface that so the
  /// user sees the real reason (validation message, "in use", "not found") rather
  /// than a bare status code. Falls back to a generic message for non-JSON bodies.
  /// The status code is always appended so callers can still branch/log on it.
  static String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final reason = decoded['detail'] ?? decoded['title'];
        if (reason is String && reason.trim().isNotEmpty) {
          return '${reason.trim()}（${response.statusCode}）';
        }
      }
    } catch (_) {
      // Not problem+json — fall through to the generic message.
    }
    return '后端请求失败（${response.statusCode}）';
  }

  void close() => _http.close();
}
