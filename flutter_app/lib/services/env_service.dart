import 'package:flutter/foundation.dart';
import '../models/env_info.dart';
import '../sidecar/sidecar_client.dart';

class EnvService extends ChangeNotifier {
  SidecarClient? _client;
  List<EnvInfo> _envs = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  String _search = '';
  int _page = 1;
  final int _pageSize = 100;

  List<EnvInfo> get envs => _envs;
  int get total => _total;
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  int get page => _page;
  int get pageSize => _pageSize;

  void setClient(SidecarClient client) {
    _client = client;
  }

  Future<void> load() async {
    if (_client == null) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _client!.listEnvs(
        search: _search,
        page: _page,
        pageSize: _pageSize,
      );
      _envs = result.data;
      _total = result.total;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    _page = 1;
    load();
  }

  void setPage(int page) {
    _page = page;
    load();
  }

  Future<void> createEnv(EnvInfo env) async {
    await _client!.createEnv(env);
    await load();
  }

  Future<void> updateEnv(int id, Map<String, dynamic> fields) async {
    await _client!.updateEnv(id, fields);
    await load();
  }

  Future<void> deleteEnv(int id) async {
    await _client!.deleteEnv(id);
    await load();
  }
}
