import '../../api/backend_client.dart';
import '../db_tools/db_tool.dart';
import '../ssh_tools/ssh_tool.dart';
import 'brokered_targets.dart';

/// Ties Access Brokering to Local Desktop Integration (ADR-0005): fetch a
/// resource's credentials on demand, hand them to the user's own tool, and keep
/// nothing. The brokered secret lives only for the duration of [launchSsh] /
/// [launchDb] — it is never written to config or otherwise persisted.
///
/// A backend/transport failure is turned into a failed [LaunchResult] carrying
/// the already-localized message, so the UI handles one result type uniformly.
class AccessLauncher {
  final BackendClient _backend;

  AccessLauncher(this._backend);

  Future<LaunchResult> launchSsh(
    int serverId,
    SshTool tool, {
    required PasswordMode preferredMode,
    String? executableOverride,
    String? startPath,
  }) async {
    try {
      final credential = await _backend.getServerCredentials(serverId);
      final target = sshTargetFromServer(credential, startPath: startPath);
      return tool.launch(
        target,
        preferredMode: preferredMode,
        executableOverride: executableOverride,
      );
    } on BackendException catch (e) {
      return LaunchResult.failure(e.message);
    }
  }

  Future<LaunchResult> launchDb(
    int databaseId,
    DbTool tool, {
    String? executableOverride,
    String? name,
  }) async {
    try {
      final credential = await _backend.getDatabaseCredentials(databaseId);
      final target = dbTargetFromDatabase(credential, name: name);
      return tool.launch(target, executableOverride: executableOverride);
    } on BackendException catch (e) {
      return LaunchResult.failure(e.message);
    }
  }
}
