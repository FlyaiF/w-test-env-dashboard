import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/backend_client.dart';
import '../services/remote_file/remote_file_session.dart';

/// Everything needed to build one [RemoteFileSession]; the store resolves it
/// from a brokered credential (plus user input when no secret is stored).
class RemoteFileSessionSpec {
  final String host;
  final int port;
  final String username;
  final String secret;
  final String path;
  final RemoteFileMode mode;

  const RemoteFileSessionSpec({
    required this.host,
    required this.port,
    required this.username,
    required this.secret,
    required this.path,
    required this.mode,
  });
}

typedef RemoteFileSessionFactory =
    RemoteFileSession Function(RemoteFileSessionSpec spec);

RemoteFileSession _defaultSessionFactory(RemoteFileSessionSpec spec) {
  return RemoteFileSession(
    host: spec.host,
    port: spec.port,
    username: spec.username,
    secret: spec.secret,
    path: spec.path,
    mode: spec.mode,
  );
}

/// One open viewer tab: display title + its live session.
class RemoteFileTab {
  final int serverId;
  final String title;
  final RemoteFileSession session;

  const RemoteFileTab({
    required this.serverId,
    required this.title,
    required this.session,
  });
}

/// Outcome of an open request. [RemoteOpenNeedsSecret] means the broker holds
/// no secret for the Server — the UI collects one (session-only, never
/// persisted) and retries via [RemoteFileStore.open] with overrides.
sealed class RemoteOpenOutcome {
  const RemoteOpenOutcome();
}

class RemoteOpenOk extends RemoteOpenOutcome {
  const RemoteOpenOk();
}

class RemoteOpenNeedsSecret extends RemoteOpenOutcome {
  final int serverId;
  final String host;
  final int port;

  /// Broker-known username to prefill the dialog, or null.
  final String? username;

  const RemoteOpenNeedsSecret({
    required this.serverId,
    required this.host,
    required this.port,
    this.username,
  });
}

class RemoteOpenFailed extends RemoteOpenOutcome {
  final String message;
  const RemoteOpenFailed(this.message);
}

/// Presentation state for the 日志文件 page: open tabs, the active tab, and
/// the "jump to the page" signal the shell listens for when a catalog row
/// action opens a file. Credentials are brokered per open and handed straight
/// to the session; the store itself keeps no secrets.
class RemoteFileStore extends ChangeNotifier {
  final BackendClient _backend;
  final RemoteFileSessionFactory _createSession;

  final List<RemoteFileTab> _tabs = [];
  int _activeIndex = 0;

  /// Bumped when an open wants the app shell to navigate to the 日志文件 page.
  int jumpSignal = 0;

  RemoteFileStore(
    this._backend, {
    RemoteFileSessionFactory sessionFactory = _defaultSessionFactory,
  }) : _createSession = sessionFactory;

  List<RemoteFileTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  RemoteFileTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Open [path] on a Server. Credentials come from the broker; pass
  /// [usernameOverride]/[secretOverride] when retrying after a
  /// [RemoteOpenNeedsSecret] round-trip. An already-open (server, path, mode)
  /// combination is focused instead of duplicated. [jumpToPage] asks the app
  /// shell to switch to the 日志文件 page on success.
  Future<RemoteOpenOutcome> open({
    required int serverId,
    required String title,
    required String path,
    required RemoteFileMode mode,
    bool jumpToPage = false,
    String? usernameOverride,
    String? secretOverride,
  }) async {
    final existing = _tabs.indexWhere(
      (t) =>
          t.serverId == serverId &&
          t.session.path == path &&
          t.session.mode == mode,
    );
    if (existing >= 0) {
      _activeIndex = existing;
      if (jumpToPage) jumpSignal++;
      notifyListeners();
      return const RemoteOpenOk();
    }

    final RemoteFileSessionSpec spec;
    try {
      final credential = await _backend.getServerCredentials(serverId);
      final host = credential.host;
      if (host == null || host.isEmpty) {
        return const RemoteOpenFailed('该服务器未配置主机地址');
      }
      final secret = secretOverride ?? credential.secret;
      if (secret == null || secret.isEmpty) {
        return RemoteOpenNeedsSecret(
          serverId: serverId,
          host: host,
          port: credential.port ?? 22,
          username: usernameOverride ?? credential.username,
        );
      }
      final username = usernameOverride ?? credential.username;
      if (username == null || username.isEmpty) {
        return RemoteOpenNeedsSecret(
          serverId: serverId,
          host: host,
          port: credential.port ?? 22,
        );
      }
      spec = RemoteFileSessionSpec(
        host: host,
        port: credential.port ?? 22,
        username: username,
        secret: secret,
        path: path,
        mode: mode,
      );
    } on BackendException catch (e) {
      return RemoteOpenFailed(e.message);
    }

    final session = _createSession(spec);
    _tabs.add(RemoteFileTab(serverId: serverId, title: title, session: session));
    _activeIndex = _tabs.length - 1;
    if (jumpToPage) jumpSignal++;
    notifyListeners();
    unawaited(session.connect());
    return const RemoteOpenOk();
  }

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// A connected session on [serverId] whose SSH connection can be borrowed
  /// for directory listings (path autocompletion), preferring the active tab.
  /// Null when no tab on that server has a live connection — completion then
  /// degrades to known-path suggestions rather than dialing a new session.
  RemoteFileSession? liveSessionFor(int serverId) {
    final active = activeTab;
    if (active != null &&
        active.serverId == serverId &&
        active.session.status == RemoteFileStatus.connected) {
      return active.session;
    }
    for (final tab in _tabs) {
      if (tab.serverId == serverId &&
          tab.session.status == RemoteFileStatus.connected) {
        return tab.session;
      }
    }
    return null;
  }

  void close(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index).session.dispose();
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex--;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.session.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
