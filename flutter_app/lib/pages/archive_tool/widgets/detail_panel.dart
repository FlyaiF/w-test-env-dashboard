import 'package:flutter/material.dart';

import '../../../src/rust/api/zipr_api.dart';

enum DetailMode { entry, diff, patch }

class DetailPanel extends StatefulWidget {
  final DetailMode mode;
  final ArchiveEntry? selectedEntry;
  final List<DiffEntry> diffEntries;
  final String? patchSpecToml;
  final List<UnresolvedEntry> unresolvedEntries;
  final VoidCallback? onPatchDraft;
  final VoidCallback? onPatchDryRun;
  final VoidCallback? onPatchApply;
  final VoidCallback? onOpenInEditor;
  final VoidCallback? onReload;
  final VoidCallback? onRestoreOriginal;
  final Future<void> Function(List<Resolution> resolutions)? onResolve;

  const DetailPanel({
    super.key,
    required this.mode,
    this.selectedEntry,
    this.diffEntries = const [],
    this.patchSpecToml,
    this.unresolvedEntries = const [],
    this.onPatchDraft,
    this.onPatchDryRun,
    this.onPatchApply,
    this.onOpenInEditor,
    this.onReload,
    this.onRestoreOriginal,
    this.onResolve,
  });

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  // Map from source path -> chosen target (null means ignore)
  final Map<String, String?> _resolutions = {};

  @override
  void didUpdateWidget(DetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unresolvedEntries != widget.unresolvedEntries) {
      _resolutions.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.mode) {
      DetailMode.entry => _buildEntryDetail(context),
      DetailMode.diff => _buildDiffView(context),
      DetailMode.patch => _buildPatchView(context),
    };
  }

  Widget _buildEntryDetail(BuildContext context) {
    if (widget.selectedEntry == null) {
      return const Center(
        child: Text('选择文件查看详情', style: TextStyle(color: Colors.grey)),
      );
    }

    final e = widget.selectedEntry!;
    final size = e.size.toInt();
    final compressed = e.compressedSize.toInt();
    final ratio = size > 0 ? (compressed / size * 100).toStringAsFixed(1) : '-';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('文件详情', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _detailRow('路径', e.expr),
          _detailRow('大小', _formatSize(size)),
          _detailRow('压缩后', _formatSize(compressed)),
          _detailRow('压缩率', '$ratio%'),
        ],
      ),
    );
  }

  Widget _buildDiffView(BuildContext context) {
    if (widget.diffEntries.isEmpty) {
      return const Center(
        child: Text('无差异', style: TextStyle(color: Colors.grey)),
      );
    }

    final added = widget.diffEntries.where((e) => e.kind == 'added').length;
    final removed = widget.diffEntries.where((e) => e.kind == 'removed').length;
    final modified = widget.diffEntries
        .where((e) => e.kind == 'modified')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('差异对比', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '新增: $added  删除: $removed  修改: $modified',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: widget.diffEntries.length,
            itemBuilder: (context, index) {
              final entry = widget.diffEntries[index];
              return _diffRow(entry);
            },
          ),
        ),
      ],
    );
  }

  Widget _diffRow(DiffEntry entry) {
    final (tag, color) = switch (entry.kind) {
      'added' => ('A', Colors.green.shade300),
      'removed' => ('D', Colors.red.shade300),
      'modified' => ('M', Colors.orange.shade300),
      _ => ('?', Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                alignment: Alignment.center,
                child: Text(
                  tag,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Sarasa Mono SC',
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.path,
                  style: const TextStyle(
                    fontFamily: 'Sarasa Mono SC',
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (entry.contentChanged)
            const Padding(
              padding: EdgeInsets.only(left: 28),
              child: Text(
                'content: changed',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          for (final meta in entry.metadataChanges)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                'meta: $meta',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPatchView(BuildContext context) {
    final hasUnresolved = widget.unresolvedEntries.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('批量替换', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Action buttons row
          Row(
            children: [
              FilledButton.icon(
                onPressed: widget.onPatchDraft,
                icon: const Icon(Icons.description, size: 18),
                label: const Text('生成清单'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.patchSpecToml != null && !hasUnresolved
                    ? widget.onPatchDryRun
                    : null,
                icon: const Icon(Icons.preview, size: 18),
                label: const Text('预演'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: widget.patchSpecToml != null && !hasUnresolved
                    ? widget.onPatchApply
                    : null,
                child: const Text('应用替换'),
              ),
            ],
          ),
          if (widget.patchSpecToml != null) ...[
            const SizedBox(height: 8),
            // Secondary action buttons
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onOpenInEditor,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('在编辑器中打开'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onReload,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '重新加载',
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onRestoreOriginal,
                  icon: const Icon(Icons.restore, size: 18),
                  tooltip: '恢复原始清单',
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Unresolved entries section
          if (hasUnresolved) ...[
            _buildUnresolvedSection(context),
            const SizedBox(height: 12),
          ],
          // TOML display
          if (widget.patchSpecToml != null) ...[
            const Text('替换清单:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.patchSpecToml!,
                    style: const TextStyle(
                      fontFamily: 'Sarasa Mono SC',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnresolvedSection(BuildContext context) {
    final entries = widget.unresolvedEntries;
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 18,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  '未解析条目 (${entries.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.orange.shade900,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _canApplyResolutions() ? _applyResolutions : null,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('应用解析'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 8),
              itemBuilder: (context, index) =>
                  _buildUnresolvedItem(entries[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnresolvedItem(UnresolvedEntry entry) {
    final sourceName = entry.source.split('/').last;
    final isMultiple = entry.reason == 'multiple targets';
    final chosen = _resolutions[entry.source];
    // null key exists means explicitly set to ignore
    final isIgnored = _resolutions.containsKey(entry.source) && chosen == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMultiple ? Icons.call_split : Icons.help_outline,
                size: 14,
                color: Colors.orange.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sourceName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Sarasa Mono SC',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isIgnored)
                TextButton(
                  onPressed: () {
                    setState(() => _resolutions[entry.source] = null);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('忽略', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          if (isIgnored)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Row(
                children: [
                  Text(
                    '已忽略',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _resolutions.remove(entry.source));
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('撤销', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            )
          else if (isMultiple && entry.candidates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: DropdownButton<String>(
                value: chosen,
                hint: const Text('选择目标...', style: TextStyle(fontSize: 11)),
                isExpanded: true,
                isDense: true,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Sarasa Mono SC',
                  color: Colors.black87,
                ),
                items: entry.candidates.map((c) {
                  return DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _resolutions[entry.source] = value);
                  }
                },
              ),
            )
          else if (!isMultiple && !isIgnored)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '未找到匹配目标',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  bool _canApplyResolutions() {
    // All unresolved entries must have a resolution (either picked or ignored)
    return widget.unresolvedEntries.isNotEmpty &&
        widget.unresolvedEntries.every(
          (e) => _resolutions.containsKey(e.source),
        );
  }

  Future<void> _applyResolutions() async {
    final resolutions = <Resolution>[];
    for (final entry in widget.unresolvedEntries) {
      final chosen = _resolutions[entry.source];
      if (chosen != null) {
        resolutions.add(
          Resolution(
            source: entry.source,
            action: 'pick',
            chosenTarget: chosen,
          ),
        );
      } else {
        resolutions.add(
          Resolution(source: entry.source, action: 'ignore', chosenTarget: ''),
        );
      }
    }
    await widget.onResolve?.call(resolutions);
    _resolutions.clear();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
