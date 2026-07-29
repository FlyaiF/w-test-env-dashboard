import 'package:flutter/foundation.dart';

import '../api/backend_client.dart';
import '../api/dto/database_dto.dart';
import '../api/dto/database_input.dart';
import '../api/dto/server_dto.dart';
import '../api/dto/server_input.dart';
import '../catalog/catalog_acl.dart';
import '../catalog/environment_view.dart';
import 'inventory_acl.dart';
import 'inventory_view.dart';

/// Canonical presentation-side state for shared Servers and Databases.
///
/// Both inventories are refreshed atomically: a failed request keeps the last
/// successfully displayed snapshot instead of replacing half of it.
class InventoryStore extends ChangeNotifier {
  final BackendClient _client;

  InventoryStore(this._client);

  List<ServerView> _servers = const [];
  List<DatabaseView> _databases = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  Future<void>? _loadFuture;

  List<ServerView> get servers => List.unmodifiable(_servers);
  List<DatabaseView> get databases => List.unmodifiable(_databases);
  Map<int, ServerView> get serversById =>
      Map.unmodifiable({for (final server in _servers) server.id: server});
  Map<int, DatabaseView> get databasesById => Map.unmodifiable({
    for (final database in _databases) database.id: database,
  });
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  /// Load the canonical inventory once, sharing an in-flight request with every
  /// caller. Catalog and Inventory pages are mounted together, so this prevents
  /// either surface from observing a false empty snapshot during startup.
  Future<void> load() => _loadFuture ??= _loadOnce().whenComplete(() {
    _loadFuture = null;
  });

  Future<void> _loadOnce() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait<Object>([
        _client.listServers(),
        _client.listDatabases(),
      ]);
      final serverDtos = results[0] as List<ServerDto>;
      final databaseDtos = results[1] as List<DatabaseDto>;
      _servers = InventoryAcl.toServerViews(serverDtos);
      _databases = InventoryAcl.toDatabaseViews(databaseDtos);
      _loaded = true;
    } on BackendException catch (exception) {
      _error = exception.message;
    } catch (exception) {
      _error = '加载资源库存失败：$exception';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> createServer(ServerInput input, {String? secret}) =>
      _mutateWithSecret(
        saveMetadata: () async => (await _client.createServer(input)).id,
        secret: secret,
        saveSecret: _client.setServerSecret,
      );

  Future<bool> updateServer(int id, ServerInput input, {String? secret}) =>
      _mutateWithSecret(
        saveMetadata: () async => (await _client.updateServer(id, input)).id,
        secret: secret,
        saveSecret: _client.setServerSecret,
      );

  Future<bool> deleteServer(int id) => _mutate(() => _client.deleteServer(id));

  Future<bool> createDatabase(DatabaseInput input, {String? secret}) =>
      _mutateWithSecret(
        saveMetadata: () async => (await _client.createDatabase(input)).id,
        secret: secret,
        saveSecret: _client.setDatabaseSecret,
      );

  Future<bool> updateDatabase(int id, DatabaseInput input, {String? secret}) =>
      _mutateWithSecret(
        saveMetadata: () async => (await _client.updateDatabase(id, input)).id,
        secret: secret,
        saveSecret: _client.setDatabaseSecret,
      );

  Future<bool> deleteDatabase(int id) =>
      _mutate(() => _client.deleteDatabase(id));

  Future<List<EnvironmentView>> environmentsOnServer(int id) async {
    final dtos = await _client.environmentsOnServer(id);
    return CatalogAcl.toViews(dtos);
  }

  Future<List<EnvironmentView>> environmentsUsingDatabase(int id) async {
    final dtos = await _client.environmentsUsingDatabase(id);
    return CatalogAcl.toViews(dtos);
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    try {
      await action();
    } on BackendException catch (exception) {
      _error = exception.message;
      notifyListeners();
      return false;
    } catch (exception) {
      _error = '操作失败：$exception';
      notifyListeners();
      return false;
    }

    await load();
    return _error == null;
  }

  /// Save non-secret metadata, then (when [secret] is non-null) hand the
  /// write-only secret to the broker. A secret failure after a successful
  /// metadata save still reloads — the metadata change is already canonical —
  /// but surfaces a targeted message so the user knows to re-enter the
  /// password, not the whole form.
  Future<bool> _mutateWithSecret({
    required Future<int> Function() saveMetadata,
    required String? secret,
    required Future<void> Function(int id, String secret) saveSecret,
  }) async {
    if (secret == null) return _mutate(saveMetadata);

    final int id;
    try {
      id = await saveMetadata();
    } on BackendException catch (exception) {
      _error = exception.message;
      notifyListeners();
      return false;
    } catch (exception) {
      _error = '操作失败：$exception';
      notifyListeners();
      return false;
    }

    String? secretFailure;
    try {
      await saveSecret(id, secret);
    } on BackendException catch (exception) {
      secretFailure = exception.message;
    } catch (exception) {
      secretFailure = '$exception';
    }

    await load();
    if (secretFailure != null) {
      _error = '信息已保存，但密码未更新：$secretFailure，请重新编辑并再次输入密码';
      notifyListeners();
      return false;
    }
    return _error == null;
  }
}
