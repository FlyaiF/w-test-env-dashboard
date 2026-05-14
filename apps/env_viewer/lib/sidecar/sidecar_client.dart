import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/env_info.dart';
import '../models/runtime_env_collection.dart';

class SidecarClient {
  final String baseUrl;

  SidecarClient(this.baseUrl);

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path'));
    final body = _decodeBody(resp, path);
    if (resp.statusCode >= 400) {
      throw SidecarException(
        body['error'] ?? 'Unknown error',
        resp.statusCode,
        detail: body['detail'] as String?,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final resp = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    final body = _decodeBody(resp, path);
    if (resp.statusCode >= 400) {
      throw SidecarException(
        body['error'] ?? 'Unknown error',
        resp.statusCode,
        detail: body['detail'] as String?,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> data,
  ) async {
    final resp = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    final body = _decodeBody(resp, path);
    if (resp.statusCode >= 400) {
      throw SidecarException(
        body['error'] ?? 'Unknown error',
        resp.statusCode,
        detail: body['detail'] as String?,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final resp = await http.delete(Uri.parse('$baseUrl$path'));
    final body = _decodeBody(resp, path);
    if (resp.statusCode >= 400) {
      throw SidecarException(
        body['error'] ?? 'Unknown error',
        resp.statusCode,
        detail: body['detail'] as String?,
      );
    }
    return body;
  }

  Map<String, dynamic> _decodeBody(http.Response resp, String path) {
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      if (resp.statusCode >= 400) {
        throw SidecarException(
          'HTTP ${resp.statusCode} $path',
          resp.statusCode,
          detail: resp.body.trim(),
        );
      }
      rethrow;
    }
  }

  // Health
  Future<bool> checkHealth() async {
    try {
      final data = await _get('/health');
      return data['db_connected'] == true;
    } catch (_) {
      return false;
    }
  }

  // Version / build info
  Future<Map<String, dynamic>> getVersion() => _get('/version');

  // List environments
  Future<({List<EnvInfo> data, int total})> listEnvs({
    String search = '',
    int page = 1,
    int pageSize = 100,
  }) async {
    var path = '/api/envs?page=$page&page_size=$pageSize';
    if (search.isNotEmpty) path += '&search=${Uri.encodeComponent(search)}';
    final body = await _get(path);
    final list = (body['data'] as List)
        .map((e) => EnvInfo.fromJson(e))
        .toList();
    return (data: list, total: body['total'] as int);
  }

  // Get single environment
  Future<EnvInfo> getEnv(int id) async {
    final body = await _get('/api/envs/$id');
    return EnvInfo.fromJson(body['data']);
  }

  // Create environment
  Future<EnvInfo> createEnv(EnvInfo env) async {
    final body = await _post('/api/envs', env.toJson());
    return EnvInfo.fromJson(body['data']);
  }

  // Update environment
  Future<EnvInfo> updateEnv(int id, Map<String, dynamic> fields) async {
    final body = await _put('/api/envs/$id', fields);
    return EnvInfo.fromJson(body['data']);
  }

  // Collect fresh runtime DB info and return a preview diff.
  Future<List<RuntimeEnvCollectionResult>> collectRuntimePreview() async {
    final body = await _post('/api/runtime-env/collect-preview', const {});
    return (body['data'] as List)
        .map((e) => RuntimeEnvCollectionResult.fromJson(e))
        .toList();
  }

  // Publish selected collected values back to TENVINFO.
  Future<RuntimePublishResult> publishCollected(
    List<RuntimeEnvCollectionResult> items,
  ) async {
    final body = await _post('/api/runtime-env/publish-collected', {
      'items': items.map((e) => e.toPublishJson()).toList(),
    });
    return RuntimePublishResult.fromJson(body);
  }

  // Delete environment
  Future<void> deleteEnv(int id) async {
    await _delete('/api/envs/$id');
  }

  // Test DB connection
  Future<String> testConnection(String dsn) async {
    final body = await _post('/api/db/test', {'dsn': dsn});
    return body['message'] as String;
  }
}

class SidecarException implements Exception {
  final String message;
  final int statusCode;
  final String? detail;

  SidecarException(this.message, this.statusCode, {this.detail});

  @override
  String toString() => detail == null ? message : '$message: $detail';
}
