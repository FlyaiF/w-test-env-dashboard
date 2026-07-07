import 'package:flutter/foundation.dart';

import '../api/backend_client.dart';
import '../api/dto/component_input.dart';
import '../api/dto/environment_input.dart';
import 'catalog_acl.dart';
import 'environment_view.dart';

/// Presentation-side state for the Environment Catalog. Replaces the old
/// god-object `EnvService`: there is no local store, no sync/merge, and no
/// database access — it fetches Environments from the backend, runs them
/// through the anti-corruption layer, exposes view models plus a client-side
/// text filter, and drives curation writes (create/update/delete) back through
/// the backend, re-fetching the canonical list after each one.
class EnvironmentStore extends ChangeNotifier {
  final BackendClient _client;

  EnvironmentStore(this._client);

  List<EnvironmentView> _all = [];
  Map<int, ServerRefView> _serverRefs = {};
  Map<int, DatabaseRefView> _databaseRefs = {};
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String _search = '';

  /// Resolved Server references by id, for rendering a Component's 运行主机 as a
  /// host instead of a bare `#id`. Empty when inventory could not be fetched.
  Map<int, ServerRefView> get serverRefs => Map.unmodifiable(_serverRefs);

  /// Resolved Database references by id, for the 数据库信息 section rows and the
  /// launch menu. Empty when inventory could not be fetched.
  Map<int, DatabaseRefView> get databaseRefs => Map.unmodifiable(_databaseRefs);

  /// Whether the backend has been reached successfully at least once. Drives the
  /// connection indicator; an error after a successful load keeps this true.
  bool get connected => _loaded;
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;

  int get totalCount => _all.length;

  /// Environments matching the current search, in backend order.
  List<EnvironmentView> get environments {
    if (_search.isEmpty) return List.unmodifiable(_all);
    final q = _search.toLowerCase();
    return _all.where((e) => _matches(e, q)).toList(growable: false);
  }

  /// Fetches the Environment list from the backend and remaps it. Errors are
  /// captured into [error] (already localized) rather than thrown to the UI.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final dtos = await _client.listEnvironments();
      _all = CatalogAcl.toViews(dtos);
      _loaded = true;
      await _loadInventoryRefs();
    } on BackendException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '加载环境失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Best-effort: resolve the shared Server/Database references for display
  /// (ADR-0006). Inventory is a display nicety, so any failure here leaves the
  /// ref maps empty (cards/menus fall back to `#id`) without disturbing the
  /// environment list or the connection state.
  Future<void> _loadInventoryRefs() async {
    try {
      final serversFuture = _client.listServers();
      final databasesFuture = _client.listDatabases();
      final servers = await serversFuture;
      final databases = await databasesFuture;
      _serverRefs = {
        for (final s in servers) s.id: CatalogAcl.serverRefView(s),
      };
      _databaseRefs = {
        for (final d in databases) d.id: CatalogAcl.databaseRefView(d),
      };
    } catch (_) {
      _serverRefs = {};
      _databaseRefs = {};
    }
  }

  /// Whether a 立即采集 request is in flight for this Environment. Drives the
  /// per-card button's spinner/disabled state.
  bool isCollecting(int environmentId) => _collecting.contains(environmentId);
  final Set<int> _collecting = {};

  /// 立即采集: ask the backend to probe this Environment now and swap the
  /// returned fresh view in place — deliberately no full list re-fetch, so the
  /// rest of the catalog is untouched. Returns null on success or a localized
  /// error message for the caller to surface (snackbar); unlike [load], it
  /// never touches [error], because a failed collection is transient and
  /// scoped to one Environment.
  Future<String?> collectNow(int environmentId) async {
    if (_collecting.contains(environmentId)) return null;
    _collecting.add(environmentId);
    notifyListeners();
    try {
      final dto = await _client.refreshEnvironment(environmentId);
      final fresh = CatalogAcl.toView(dto);
      final index = _all.indexWhere((e) => e.id == environmentId);
      if (index >= 0) {
        _all = List.of(_all)..[index] = fresh;
      }
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (e) {
      return '采集失败：$e';
    } finally {
      _collecting.remove(environmentId);
      notifyListeners();
    }
  }

  void setSearch(String value) {
    final next = value.trim();
    if (next == _search) return;
    _search = next;
    notifyListeners();
  }

  /// Create an Environment, then refresh from the backend. Returns true on
  /// success; on failure leaves [error] set (already localized) and returns
  /// false so the caller can keep the edit form open.
  Future<bool> createEnvironment(EnvironmentInput input) =>
      _mutate(() => _client.createEnvironment(input));

  /// Update an Environment's own fields (name, memo); Components are unaffected.
  Future<bool> updateEnvironment(int id, EnvironmentInput input) =>
      _mutate(() => _client.updateEnvironment(id, input));

  /// Delete an Environment; the backend cascades to its Components only.
  Future<bool> deleteEnvironment(int id) =>
      _mutate(() => _client.deleteEnvironment(id));

  /// Add a Component to an Environment.
  Future<bool> addComponent(int environmentId, ComponentInput input) =>
      _mutate(() => _client.addComponent(environmentId, input));

  /// Update one Component, scoped to its owning Environment.
  Future<bool> updateComponent(
    int environmentId,
    int componentId,
    ComponentInput input,
  ) => _mutate(() => _client.updateComponent(environmentId, componentId, input));

  /// Remove one Component from its owning Environment.
  Future<bool> removeComponent(int environmentId, int componentId) =>
      _mutate(() => _client.deleteComponent(environmentId, componentId));

  /// Run a write against the backend, then re-fetch the canonical list so the UI
  /// reflects exactly what the server stored. Errors are captured into [error]
  /// rather than thrown to the widget.
  Future<bool> _mutate(Future<void> Function() action) async {
    try {
      await action();
    } on BackendException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '操作失败：$e';
      notifyListeners();
      return false;
    }
    await load();
    return true;
  }

  static bool _matches(EnvironmentView env, String lowerQuery) {
    if (env.id.toString().contains(lowerQuery)) return true;
    if (env.name.toLowerCase().contains(lowerQuery)) return true;
    if (env.memo?.toLowerCase().contains(lowerQuery) ?? false) return true;
    for (final c in env.components) {
      if (c.roleLabel.toLowerCase().contains(lowerQuery)) return true;
      if (c.version?.toLowerCase().contains(lowerQuery) ?? false) return true;
      if (c.url?.toLowerCase().contains(lowerQuery) ?? false) return true;
    }
    return false;
  }
}
