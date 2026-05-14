import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/environment.dart';
import '../models/server.dart';

class LocalStore extends ChangeNotifier {
  static const _dirName = '.test-env-dashboard';
  static const _fileName = 'local_data.json';

  Map<String, Server> _servers = {};
  List<Environment> _environments = [];

  Map<String, Server> get servers => Map.unmodifiable(_servers);
  List<Environment> get environments => List.unmodifiable(_environments);

  // ---- File I/O ----

  static Future<File> _dataFile() async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$home/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    try {
      final file = await _dataFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _deserialize(json);
      }
    } catch (e) {
      debugPrint('LocalStore.load error: $e');
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final file = await _dataFile();
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_serialize()));
    } catch (e) {
      debugPrint('LocalStore.save error: $e');
    }
  }

  // ---- Serialization ----

  Map<String, dynamic> _serialize() {
    return {
      'servers': _servers.map((k, v) => MapEntry(k, v.toJson())),
      'environments': _environments.map((e) => e.toJson()).toList(),
    };
  }

  void _deserialize(Map<String, dynamic> json) {
    final serversJson = json['servers'] as Map<String, dynamic>? ?? {};
    _servers = serversJson.map(
      (k, v) => MapEntry(k, Server.fromJson(v as Map<String, dynamic>)),
    );

    final envsJson = json['environments'] as List<dynamic>? ?? [];
    _environments =
        envsJson
            .map((e) => Environment.fromJson(e as Map<String, dynamic>))
            .toList();
  }

  // ---- Server CRUD ----

  Server? getServerByHost(String host) => _servers[host];

  void upsertServer(Server server) {
    final existing = _servers[server.host];
    if (existing != null && existing.isLocalOnly && !server.isLocalOnly) {
      // Don't overwrite local-only server with a remote-sourced one;
      // just update credentials if they came from remote.
      _servers[server.host] = existing.copyWith(
        port: server.port,
        sshUsername: server.sshUsername,
        sshPassword: server.sshPassword,
      );
    } else if (existing != null) {
      // Preserve local-only fields (label) when updating from remote.
      _servers[server.host] = server.copyWith(label: existing.label);
    } else {
      _servers[server.host] = server;
    }
    notifyListeners();
  }

  void addServer(Server server) {
    _servers[server.host] = server;
    notifyListeners();
  }

  void updateServer(String host, Server server) {
    if (host != server.host) {
      _servers.remove(host);
      // Re-link environments that referenced the old host.
      _environments =
          _environments
              .map(
                (e) =>
                    e.serverHost == host
                        ? e.copyWith(serverHost: server.host)
                        : e,
              )
              .toList();
    }
    _servers[server.host] = server;
    notifyListeners();
  }

  void removeServer(String host) {
    _servers.remove(host);
    // Clear serverHost on environments that referenced this server.
    _environments =
        _environments
            .map(
              (e) =>
                  e.serverHost == host
                      ? Environment(
                          eNo: e.eNo,
                          name: e.name,
                          url: e.url,
                          seeUrl: e.seeUrl,
                          version: e.version,
                          ywdb: e.ywdb,
                          zjdb: e.zjdb,
                          dbType: e.dbType,
                          webLogPath: e.webLogPath,
                          memo: e.memo,
                          updateTime: e.updateTime,
                          serverHost: null,
                          webserverAddrRaw: e.webserverAddrRaw,
                          lastSyncedAt: e.lastSyncedAt,
                        )
                      : e,
            )
            .toList();
    notifyListeners();
  }

  // ---- Environment CRUD ----

  Environment? getEnvironmentByNo(int eNo) {
    try {
      return _environments.firstWhere((e) => e.eNo == eNo);
    } catch (_) {
      return null;
    }
  }

  void upsertEnvironment(Environment env) {
    final idx = _environments.indexWhere((e) => e.eNo == env.eNo);
    if (idx >= 0) {
      _environments[idx] = env;
    } else {
      _environments.add(env);
    }
    notifyListeners();
  }

  void removeEnvironment(int eNo) {
    _environments.removeWhere((e) => e.eNo == eNo);
    notifyListeners();
  }

  /// Replace all environments (used during full sync).
  void setEnvironments(List<Environment> envs) {
    _environments = envs;
    notifyListeners();
  }
}
