import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../remote_files/remote_file_store.dart';
import '../../services/remote_file/line_buffer.dart';
import '../../services/remote_file/remote_file_session.dart';

/// Read-only rendering of one open remote file: status/tools bar on top, the
/// (ring-buffered) content below. 跟随 tabs render newest-at-bottom and stick
/// there; 查看 tabs render top-down with a truncation notice when capped.
class RemoteFileViewer extends StatelessWidget {
  final RemoteFileTab tab;

  const RemoteFileViewer({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    final session = tab.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final tokens = AppTokens.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(tab: tab),
            if (session.truncated)
              MaterialBanner(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                content: Text(
                  '文件超过 ${kViewModeByteCap ~/ (1024 * 1024)} MB，仅显示开头部分 — 可用「下载」获取完整文件',
                  style: const TextStyle(fontSize: 12.5),
                ),
                actions: const [SizedBox.shrink()],
              ),
            if (session.status == RemoteFileStatus.failed)
              Expanded(child: _FailureBody(session: session))
            else
              Expanded(
                child: ColoredBox(
                  color: tokens.cardBodyBg,
                  child: session.buffer.isEmpty
                      ? Center(
                          child: session.status == RemoteFileStatus.connecting
                              ? const CircularProgressIndicator()
                              : Text(
                                  '（空文件）',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                        )
                      : _LineList(session: session),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  final RemoteFileTab tab;

  const _Toolbar({required this.tab});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final session = tab.session;
    final follow = session.mode == RemoteFileMode.follow;

    final (chipKind, chipLabel) = switch (session.status) {
      RemoteFileStatus.connecting => (StatusChipKind.none, '连接中'),
      RemoteFileStatus.connected when session.paused => (
        StatusChipKind.na,
        '已暂停',
      ),
      RemoteFileStatus.connected => (
        StatusChipKind.ok,
        follow ? '跟随中' : '已读取',
      ),
      RemoteFileStatus.disconnected => (StatusChipKind.err, '已断开'),
      RemoteFileStatus.failed => (StatusChipKind.err, '失败'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: tokens.tableHeaderBg,
      child: Row(
        children: [
          StatusChip(kind: chipKind, label: chipLabel),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message:
                  '${session.username}@${session.host}:${session.port} ${session.path}',
              child: Text(
                '${tab.title}   ${session.path}',
                style: tokens.mono(fontSize: 11.5, color: tokens.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<RemoteFileEncoding>(
              value: session.encoding,
              isDense: true,
              style: tokens.mono(fontSize: 11.5),
              items: [
                for (final enc in RemoteFileEncoding.values)
                  DropdownMenuItem(value: enc, child: Text(enc.label)),
              ],
              onChanged: (enc) {
                if (enc != null) session.encoding = enc;
              },
            ),
          ),
          if (follow && session.status == RemoteFileStatus.connected)
            IconButton(
              icon: Icon(session.paused ? Icons.play_arrow : Icons.pause,
                  size: 16),
              tooltip: session.paused ? '继续' : '暂停',
              visualDensity: VisualDensity.compact,
              onPressed: session.togglePause,
            ),
          if (!follow)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              onPressed: session.status == RemoteFileStatus.connecting
                  ? null
                  : session.refresh,
            ),
          if (session.status == RemoteFileStatus.disconnected ||
              session.status == RemoteFileStatus.failed)
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 16),
              tooltip: '重连',
              visualDensity: VisualDensity.compact,
              onPressed: session.reconnect,
            ),
          IconButton(
            icon: const Icon(Icons.download, size: 16),
            tooltip: '下载完整文件',
            visualDensity: VisualDensity.compact,
            onPressed: session.status == RemoteFileStatus.connected ||
                    session.status == RemoteFileStatus.disconnected
                ? () => _download(context, session)
                : null,
          ),
        ],
      ),
    );
  }

  /// SFTP the whole remote file to a user-chosen location, with a modal
  /// progress dialog for large files.
  Future<void> _download(BuildContext context, RemoteFileSession session) async {
    final suggested = session.path.split('/').lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => 'remote-file',
    );
    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null || !context.mounted) return;

    final progress = ValueNotifier<(int, int?)>((0, null));
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('下载中'),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: progress,
          builder: (ctx, value, _) {
            final (written, total) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (total == null || total == 0)
                      ? null
                      : written / total,
                ),
                const SizedBox(height: 8),
                Text(
                  total == null
                      ? _formatBytes(written)
                      : '${_formatBytes(written)} / ${_formatBytes(total)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    String? error;
    try {
      await session.download(
        location.path,
        onProgress: (written, total) => progress.value = (written, total),
      );
    } catch (e) {
      error = '下载失败：$e';
    }
    if (!context.mounted) return;
    if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已下载到 ${location.path}')),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FailureBody extends StatelessWidget {
  final RemoteFileSession session;

  const _FailureBody({required this.session});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: tokens.err),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SelectableText(
              session.statusDetail ?? '连接失败',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('重连'),
            onPressed: session.reconnect,
          ),
        ],
      ),
    );
  }
}

class _LineList extends StatelessWidget {
  final RemoteFileSession session;

  const _LineList({required this.session});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final buffer = session.buffer;
    final follow = session.mode == RemoteFileMode.follow;
    return SelectionArea(
      child: ListView.builder(
        // 跟随: reversed so the newest line hugs the bottom and the view
        // sticks there as lines stream in.
        reverse: follow,
        padding: const EdgeInsets.all(10),
        itemCount: buffer.length,
        itemBuilder: (context, i) {
          final line = buffer.lineAt(follow ? buffer.length - 1 - i : i);
          final isErr = line.contains('ERROR');
          final isWarn = !isErr && line.contains('WARN');
          return Text(
            line.isEmpty ? ' ' : line,
            style: tokens.mono(
              fontSize: 12,
              color: isErr
                  ? tokens.err
                  : isWarn
                      ? tokens.warn
                      : null,
            ),
          );
        },
      ),
    );
  }
}
