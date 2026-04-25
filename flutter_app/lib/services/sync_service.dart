import 'package:flutter/foundation.dart';

import '../models/env_info.dart';
import '../models/environment.dart';
import '../models/server.dart';
import '../sidecar/sidecar_client.dart';
import '../utils/addr_parser.dart';
import 'local_store.dart';

class SyncService {
  final SidecarClient _client;
  final LocalStore _store;

  SyncService(this._client, this._store);

  /// Fetch all environments from remote Oracle and merge into local store.
  Future<void> syncFromRemote() async {
    try {
      final allEnvs = await _fetchAllPages();
      final now = DateTime.now();

      for (final envInfo in allEnvs) {
        // Parse server info and upsert server.
        if (envInfo.eWebserveraddr != null &&
            envInfo.eWebserveraddr!.isNotEmpty) {
          final parsed = parseServerAddr(envInfo.eWebserveraddr!);
          if (parsed.host.isNotEmpty) {
            _store.upsertServer(
              Server(
                host: parsed.host,
                port: parsed.port,
                sshUsername: parsed.username,
                sshPassword: parsed.password,
              ),
            );
          }
        }

        // Map EnvInfo → Environment and upsert.
        final serverHost = extractHost(envInfo.eWebserveraddr);
        _store.upsertEnvironment(
          toEnvironment(
            envInfo,
            serverHost: serverHost,
            syncedAt: now,
            existing: _store.getEnvironmentByNo(envInfo.eNo),
          ),
        );
      }

      await _store.save();
      debugPrint('SyncService: synced ${allEnvs.length} environments');
    } catch (e) {
      debugPrint('SyncService.syncFromRemote error: $e');
      rethrow;
    }
  }

  /// Fetch all pages from the remote sidecar.
  Future<List<EnvInfo>> _fetchAllPages() async {
    const pageSize = 100;
    final firstPage = await _client.listEnvs(page: 1, pageSize: pageSize);
    final all = List<EnvInfo>.from(firstPage.data);
    final total = firstPage.total;

    var page = 2;
    while (all.length < total) {
      final next = await _client.listEnvs(page: page, pageSize: pageSize);
      all.addAll(next.data);
      page++;
    }
    return all;
  }

  static String? extractHost(String? webserveraddr) {
    if (webserveraddr == null || webserveraddr.isEmpty) return null;
    final parsed = parseServerAddr(webserveraddr);
    return parsed.host.isNotEmpty ? parsed.host : null;
  }

  static Environment toEnvironment(
    EnvInfo info, {
    String? serverHost,
    DateTime? syncedAt,
    Environment? existing,
  }) {
    // Preserve local-only fields from existing record.
    return Environment(
      eNo: info.eNo,
      name: info.eName,
      url: info.eUrl,
      seeUrl: info.eSeeurl,
      version: info.eVersion,
      ywdb: info.eYwdb,
      zjdb: info.eZjdb,
      dbType: info.eDbtype,
      webLogPath: info.eWeblogpath,
      memo: info.eMemo,
      updateTime: info.eUpdatetime,
      serverHost: serverHost,
      webserverAddrRaw: info.eWebserveraddr,
      lastSyncedAt: syncedAt ?? existing?.lastSyncedAt,
    );
  }
}
