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
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String _search = '';

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
    } on BackendException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '加载环境失败：$e';
    } finally {
      _loading = false;
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
