import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'dto/environment_dto.dart';

/// Raised when the backend cannot be reached or returns a non-2xx response.
/// Carries a human-readable, already-localized message for the UI.
class BackendException implements Exception {
  final String message;
  const BackendException(this.message);

  @override
  String toString() => message;
}

/// HTTP client to the backend Environment Catalog read API (slice 01):
/// `GET /api/environments` and `GET /api/environments/{id}`. This is the only
/// way the thin client obtains environment data — there is no local store and
/// no database access. It returns raw DTOs; the anti-corruption layer maps them
/// to view models.
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

  Future<dynamic> _getJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response response;
    try {
      response = await _http.get(uri, headers: {'Accept': 'application/json'});
    } on SocketException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    } on http.ClientException {
      throw const BackendException('无法连接后端服务，请确认服务已启动');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException('后端请求失败（${response.statusCode}）');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const BackendException('后端返回了无法解析的数据');
    }
  }

  void close() => _http.close();
}
