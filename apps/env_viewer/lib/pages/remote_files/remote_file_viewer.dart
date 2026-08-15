import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                  child: session.visibleLineCount == 0
                      ? Center(
                          child: session.status == RemoteFileStatus.connecting
                              ? const CircularProgressIndicator()
                              : Text(
                                  session.viewClearedAt > 0
                                      ? '已清空，等待新输出'
                                      : '（空文件）',
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
          if (follow)
            IconButton(
              icon: const Icon(Icons.clear_all, size: 16),
              tooltip: '清空显示',
              visualDensity: VisualDensity.compact,
              onPressed:
                  session.visibleLineCount == 0 ? null : session.clearView,
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
            icon: const Icon(Icons.copy_all, size: 16),
            tooltip: '复制全部',
            visualDensity: VisualDensity.compact,
            onPressed: session.visibleLineCount == 0
                ? null
                : () => _copyVisible(context, session),
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

/// Copy every visible line — from the 清空 marker onward; the ring may have
/// dropped older lines — with the platform's line ending, so pastes keep
/// their lines even in EOL-picky Windows editors.
Future<void> _copyVisible(
  BuildContext context,
  RemoteFileSession session,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final buffer = session.buffer;
  final eol = Platform.isWindows ? '\r\n' : '\n';
  final text = StringBuffer();
  var lines = 0;
  for (var i = session.visibleStart; i < buffer.length; i++) {
    if (lines++ > 0) text.write(eol);
    text.write(buffer.lineAt(i));
  }
  await Clipboard.setData(ClipboardData(text: text.toString()));
  messenger.showSnackBar(
    SnackBar(content: Text('已复制 $lines 行')),
  );
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
    return SelectionArea(child: _ChunkedLines(session: session));
  }
}

/// The line paragraphs. One `Text` per line would break multi-line copy
/// (`SelectionArea` concatenates per-widget selections with no `\n` between
/// them), so lines render in fixed-size chunks that the ListView virtualizes.
///
/// Chunks are anchored to *absolute* line numbers — chunk k always holds
/// lines [k·size, (k+1)·size) of everything ever appended — and keyed by that
/// index. Because the ring evicts in whole chunks, a filled chunk's text
/// never changes again, and `RenderParagraph` only preserves a selection
/// across rebuilds when its text is identical: anchoring is what keeps a
/// selection alive while the tail streams. While a selection drag is in
/// progress the rendered tail is additionally frozen and ring eviction held,
/// so not even the newest, still-filling chunk mutates mid-gesture.
class _ChunkedLines extends StatefulWidget {
  final RemoteFileSession session;

  const _ChunkedLines({required this.session});

  @override
  State<_ChunkedLines> createState() => _ChunkedLinesState();
}

class _ChunkedLinesState extends State<_ChunkedLines> {
  ValueListenable<SelectableRegionSelectionStatus>? _selectionStatus;

  /// Absolute committed-line count when the in-progress drag started, or
  /// null when no drag is active. Rendering is capped here while set.
  int? _frozenEnd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final status = SelectableRegionSelectionStatusScope.maybeOf(context);
    if (identical(status, _selectionStatus)) return;
    _selectionStatus?.removeListener(_onSelectionStatus);
    _selectionStatus = status;
    status?.addListener(_onSelectionStatus);
  }

  @override
  void dispose() {
    _selectionStatus?.removeListener(_onSelectionStatus);
    if (_frozenEnd != null) widget.session.buffer.holdEviction = false;
    super.dispose();
  }

  void _onSelectionStatus() {
    final changing =
        _selectionStatus?.value == SelectableRegionSelectionStatus.changing;
    if (changing && _frozenEnd == null) {
      // No setState: freezing at the current edge changes nothing on screen.
      _frozenEnd = widget.session.buffer.totalAppended;
      widget.session.buffer.holdEviction = true;
    } else if (!changing && _frozenEnd != null) {
      setState(() {
        _frozenEnd = null;
        widget.session.buffer.holdEviction = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final session = widget.session;
    final buffer = session.buffer;
    final chunkSize = buffer.evictionChunk;
    final follow = session.mode == RemoteFileMode.follow;

    final firstAbs = buffer.firstRetained;
    final startAbs = firstAbs + session.visibleStart;
    var endAbs = buffer.totalAppended;
    final frozen = _frozenEnd;
    if (frozen != null && frozen < endAbs) endAbs = frozen;
    if (endAbs <= startAbs) return const SizedBox.shrink();

    final firstChunk = startAbs ~/ chunkSize;
    final chunkCount = (endAbs - 1) ~/ chunkSize - firstChunk + 1;

    return ListView.builder(
      // 跟随: reversed so the newest line hugs the bottom and the view
      // sticks there as lines stream in.
      reverse: follow,
      padding: const EdgeInsets.all(10),
      itemCount: chunkCount,
      // With keys, index shifts (new chunks in follow mode, whole-chunk
      // eviction) reuse the existing elements instead of rebuilding
      // paragraphs with foreign text — which would kill their selections.
      findChildIndexCallback: (key) {
        final chunk = (key as ValueKey<int>).value - firstChunk;
        if (chunk < 0 || chunk >= chunkCount) return null;
        return follow ? chunkCount - 1 - chunk : chunk;
      },
      itemBuilder: (context, i) {
        final chunk = firstChunk + (follow ? chunkCount - 1 - i : i);
        var start = chunk * chunkSize;
        if (start < startAbs) start = startAbs;
        var end = (chunk + 1) * chunkSize;
        if (end > endAbs) end = endAbs;

        final spans = <TextSpan>[];
        for (var l = start; l < end; l++) {
          final line = buffer.lineAt(l - firstAbs);
          final isErr = line.contains('ERROR');
          final isWarn = !isErr && line.contains('WARN');
          spans.add(
            TextSpan(
              text: l == start ? line : '\n$line',
              style: isErr
                  ? TextStyle(color: tokens.err)
                  : isWarn
                      ? TextStyle(color: tokens.warn)
                      : null,
            ),
          );
        }
        // Chunk-boundary newline: copied as a line break, rendered at
        // near-zero height so no visible blank line appears every chunk.
        // Unconditional, so a chunk's text is final the moment it fills.
        spans.add(
          const TextSpan(text: '\n', style: TextStyle(fontSize: 0.1)),
        );
        return KeyedSubtree(
          key: ValueKey<int>(chunk),
          child: Text.rich(
            TextSpan(style: tokens.mono(fontSize: 12), children: spans),
          ),
        );
      },
    );
  }
}
