import 'package:flutter/foundation.dart';
import '../models/env_info.dart';
import '../models/environment.dart';
import '../models/server.dart';
import '../sidecar/sidecar_client.dart';
import 'local_store.dart';
import 'sync_service.dart';

class EnvService extends ChangeNotifier {
  SidecarClient? _client;
  LocalStore? _store;
  SyncService? _syncService;

  List<EnvInfo> _envs = [];
  int _total = 0;
  bool _loading = false;
  bool _syncing = false;
  String? _error;
  String _search = '';
  int _page = 1;
  final int _pageSize = 100;

  List<EnvInfo> get envs => _envs;
  int get total => _total;
  bool get loading => _loading;
  bool get syncing => _syncing;
  String? get error => _error;
  String get search => _search;
  int get page => _page;
  int get pageSize => _pageSize;

  void setLocalStore(LocalStore store) {
    _store = store;
  }

  void setClient(SidecarClient client) {
    _client = client;
    if (_store != null) {
      _syncService = SyncService(client, _store!);
    }
  }

  /// Load environments from local store with search/pagination.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (_store != null) {
        _loadFromLocal();
      } else if (_client != null) {
        // Fallback: direct remote fetch (no local store yet).
        final result = await _client!.listEnvs(
          search: _search,
          page: _page,
          pageSize: _pageSize,
        );
        _envs = result.data;
        _total = result.total;
      }
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  void _loadFromLocal() {
    var envs = _store!.environments;

    // Apply search filter locally.
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      envs =
          envs.where((e) {
            return (e.name?.toLowerCase().contains(q) ?? false) ||
                (e.url?.toLowerCase().contains(q) ?? false) ||
                (e.memo?.toLowerCase().contains(q) ?? false) ||
                (e.version?.toLowerCase().contains(q) ?? false);
          }).toList();
    }

    _total = envs.length;

    // Apply pagination.
    final start = (_page - 1) * _pageSize;
    final end = start + _pageSize;
    final paged =
        envs.sublist(
          start.clamp(0, envs.length),
          end.clamp(0, envs.length),
        );

    // Convert Environment → EnvInfo for backward compatibility with UI.
    _envs = paged.map(_toEnvInfo).toList();
  }

  /// Sync from remote Oracle, then reload from local store.
  Future<void> sync() async {
    if (_syncService == null) return;
    _syncing = true;
    _error = null;
    notifyListeners();

    try {
      await _syncService!.syncFromRemote();
      _loadFromLocal();
    } catch (e) {
      _error = '同步失败: $e';
    }
    _syncing = false;
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

  // ---- Remote CUD (write to Oracle, then sync back) ----

  Future<void> createEnv(EnvInfo env) async {
    await _client!.createEnv(env);
    await sync();
  }

  Future<void> updateEnv(int id, Map<String, dynamic> fields) async {
    await _client!.updateEnv(id, fields);
    await sync();
  }

  Future<void> deleteEnv(int id) async {
    await _client!.deleteEnv(id);
    _store?.removeEnvironment(id);
    await _store?.save();
    await load();
  }

  // ---- Local data accessors ----

  Server? getServerForEnv(int eNo) {
    if (_store == null) return null;
    final env = _store!.getEnvironmentByNo(eNo);
    if (env?.serverHost == null) return null;
    return _store!.getServerByHost(env!.serverHost!);
  }

  List<Server> get servers =>
      _store?.servers.values.toList() ?? [];

  LocalStore? get localStore => _store;

  // ---- Conversion helpers ----

  static EnvInfo _toEnvInfo(Environment e) {
    return EnvInfo(
      eNo: e.eNo,
      eName: e.name,
      eYwdb: e.ywdb,
      eZjdb: e.zjdb,
      eUrl: e.url,
      eVersion: e.version,
      eUpdatetime: e.updateTime,
      eSeeurl: e.seeUrl,
      eWebserveraddr: e.webserverAddrRaw,
      eWeblogpath: e.webLogPath,
      eMemo: e.memo,
      eDbtype: e.dbType,
    );
  }
}
