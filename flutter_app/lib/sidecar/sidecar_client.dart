import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/env_info.dart';

class SidecarClient {
  final String baseUrl;

  SidecarClient(this.baseUrl);

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path'));
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw SidecarException(body['error'] ?? 'Unknown error', resp.statusCode);
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
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw SidecarException(body['error'] ?? 'Unknown error', resp.statusCode);
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
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw SidecarException(body['error'] ?? 'Unknown error', resp.statusCode);
    }
    return body;
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final resp = await http.delete(Uri.parse('$baseUrl$path'));
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw SidecarException(body['error'] ?? 'Unknown error', resp.statusCode);
    }
    return body;
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

  SidecarException(this.message, this.statusCode);

  @override
  String toString() => message;
}
