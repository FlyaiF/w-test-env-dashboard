import 'package:flutter/material.dart';

import '../../remote_files/remote_file_store.dart';
import '../../services/remote_file/remote_file_session.dart';

/// Shared open flow for a remote file (catalog row action and 日志文件 page):
/// try the silent brokered open; when the broker has no secret, collect one in
/// a dialog (used for this session only, never persisted) and retry. Failures
/// surface as a SnackBar.
Future<void> openRemoteFile(
  BuildContext context, {
  required RemoteFileStore store,
  required int serverId,
  required String title,
  required String path,
  required RemoteFileMode mode,
  bool jumpToPage = false,
}) async {
  var outcome = await store.open(
    serverId: serverId,
    title: title,
    path: path,
    mode: mode,
    jumpToPage: jumpToPage,
  );
  if (outcome is RemoteOpenNeedsSecret) {
    if (!context.mounted) return;
    final entered = await _showSshCredentialDialog(context, outcome);
    if (entered == null || !context.mounted) return;
    outcome = await store.open(
      serverId: serverId,
      title: title,
      path: path,
      mode: mode,
      jumpToPage: jumpToPage,
      usernameOverride: entered.username,
      secretOverride: entered.secret,
    );
  }
  if (outcome is RemoteOpenFailed && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(outcome.message)));
  }
}

class _EnteredCredential {
  final String username;
  final String secret;
  const _EnteredCredential(this.username, this.secret);
}

/// Session-only SSH credential prompt, shown when the broker has no stored
/// secret for the Server. Nothing typed here is written anywhere.
Future<_EnteredCredential?> _showSshCredentialDialog(
  BuildContext context,
  RemoteOpenNeedsSecret needs,
) async {
  final usernameCtrl = TextEditingController(text: needs.username ?? '');
  final passwordCtrl = TextEditingController();
  final result = await showDialog<_EnteredCredential>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('连接 ${needs.host}:${needs.port}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '该服务器未存储 SSH 密码，输入的凭据仅用于本次连接。',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(
                _EnteredCredential(
                  usernameCtrl.text.trim(),
                  passwordCtrl.text,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(
            _EnteredCredential(usernameCtrl.text.trim(), passwordCtrl.text),
          ),
          child: const Text('连接'),
        ),
      ],
    ),
  );
  usernameCtrl.dispose();
  passwordCtrl.dispose();
  if (result == null || result.username.isEmpty || result.secret.isEmpty) {
    return null;
  }
  return result;
}
