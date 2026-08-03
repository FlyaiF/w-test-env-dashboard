import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' as ui;

import '../services/update/app_update_store.dart';

/// The whole visible surface of self-update: nothing until the backend offers
/// a newer build, then an accent-filled download icon in the scaffold header.
/// Deliberately not a dialog or banner — updating is always the user's move.
class UpdateButton extends StatelessWidget {
  const UpdateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final update = context.select<AppUpdateStore, String?>(
      (s) => s.available?.version,
    );
    if (update == null) return const SizedBox.shrink();
    final tokens = ui.AppTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: '发现新版本 $update，点击更新',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _showUpdateDialog(context),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.download, size: 14, color: tokens.onAccent),
          ),
        ),
      ),
    );
  }

  void _showUpdateDialog(BuildContext context) {
    final store = context.read<AppUpdateStore>();
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<AppUpdateStore>.value(
        value: store,
        child: const _UpdateDialog(),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppUpdateStore>();
    final update = store.available;
    if (update == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = ui.AppTokens.of(context);
    final notes = update.notes?.trim();

    return AlertDialog(
      title: Text('新版本 ${update.version}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notes != null && notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Text(notes, style: theme.textTheme.bodyMedium),
                ),
              )
            else
              Text(
                '更新完成后应用会自动重启。',
                style: theme.textTheme.bodyMedium,
              ),
            if (store.busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: store.progress),
              const SizedBox(height: 6),
              Text(
                '正在下载… ${(store.progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (store.error != null) ...[
              const SizedBox(height: 12),
              Text(
                store.error!,
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.err),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: store.busy ? null : () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: store.busy ? null : store.downloadAndRestart,
          child: Text(store.error == null ? '立即更新' : '重试'),
        ),
      ],
    );
  }
}
