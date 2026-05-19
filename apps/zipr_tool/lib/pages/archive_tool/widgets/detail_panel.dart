import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../src/rust/api/zipr_api.dart';

enum DetailMode { entry, diff, patch }

class DetailPanel extends StatefulWidget {
  final DetailMode mode;
  final ArchiveEntry? selectedEntry;
  final List<DiffEntry> diffEntries;
  final String? patchSpecToml;
  final List<UnresolvedEntry> unresolvedEntries;
  final VoidCallback? onPatchDraftExtend;
  final VoidCallback? onPatchDiscard;
  final ValueChanged<List<String>>? onPatchSourcesDropped;
  final VoidCallback? onPatchDryRun;
  final VoidCallback? onPatchApply;
  final VoidCallback? onOpenInEditor;
  final VoidCallback? onReload;
  final VoidCallback? onRestoreOriginal;
  final VoidCallback? onRollbackArchive;
  final VoidCallback? onClose;
  final Future<void> Function(List<Resolution> resolutions)? onResolve;
  final bool canRollback;

  const DetailPanel({
    super.key,
    required this.mode,
    this.selectedEntry,
    this.diffEntries = const [],
    this.patchSpecToml,
    this.unresolvedEntries = const [],
    this.onPatchDraftExtend,
    this.onPatchDiscard,
    this.onPatchSourcesDropped,
    this.onPatchDryRun,
    this.onPatchApply,
    this.onOpenInEditor,
    this.onReload,
    this.onRestoreOriginal,
    this.onRollbackArchive,
    this.onClose,
    this.onResolve,
    this.canRollback = false,
  });

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  // Map from source path -> chosen target (null means ignore)
  final Map<String, String?> _resolutions = {};
  bool _isPatchDropHover = false;

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
              return _diffRow(context, entry);
            },
          ),
        ),
      ],
    );
  }

  Widget _diffRow(BuildContext context, DiffEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
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
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                'content: changed',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final meta in entry.metadataChanges)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                'meta: $meta',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPatchView(BuildContext context) {
    final hasUnresolved = widget.unresolvedEntries.isNotEmpty;
    final hasSpec = widget.patchSpecToml != null;
    final entryCount = _patchEntryCount(widget.patchSpecToml);
    final summary = hasSpec
        ? '清单：$entryCount 项匹配 · ${widget.unresolvedEntries.length} 项未解析'
        : '拖入文件或目录，生成替换清单后再 dry-run、替换';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('批量替换', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '返回浏览',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(summary, style: _mutedTextStyle(context)),
          const SizedBox(height: 12),
          _buildPatchDropZone(context, hasSpec),
          const SizedBox(height: 12),
          _buildPatchActionBar(context, hasSpec, hasUnresolved),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (hasUnresolved) ...[
                  _buildUnresolvedSection(context),
                  const SizedBox(height: 12),
                ],
                if (widget.patchSpecToml != null)
                  _buildPatchSpecDisclosure(context, widget.patchSpecToml!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatchActionBar(
    BuildContext context,
    bool hasSpec,
    bool hasUnresolved,
  ) {
    final canRun = hasSpec && !hasUnresolved;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasSpec) ...[
          OutlinedButton.icon(
            onPressed: canRun ? widget.onPatchDryRun : null,
            icon: const Icon(Icons.preview, size: 18),
            label: const Text('dry-run'),
          ),
          FilledButton.tonalIcon(
            onPressed: canRun ? widget.onPatchApply : null,
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('替换'),
          ),
          OutlinedButton.icon(
            onPressed: widget.onPatchDiscard,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('取消'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          IconButton(
            onPressed: widget.onOpenInEditor,
            icon: const Icon(Icons.edit_note, size: 18),
            tooltip: '在编辑器中打开清单',
          ),
          IconButton(
            onPressed: widget.onReload,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '从磁盘重新加载清单',
          ),
          IconButton(
            onPressed: widget.onRestoreOriginal,
            icon: const Icon(Icons.restore_page, size: 18),
            tooltip: '恢复清单到生成时状态（不影响归档）',
          ),
          if (widget.canRollback)
            IconButton(
              onPressed: widget.onRollbackArchive,
              icon: const Icon(Icons.undo, size: 18),
              tooltip: '回滚归档到上次备份',
              color: Theme.of(context).colorScheme.error,
            ),
        ],
      ],
    );
  }

  Widget _buildPatchDropZone(BuildContext context, bool hasSpec) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = _isPatchDropHover
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final background = _isPatchDropHover
        ? colorScheme.primary.withValues(alpha: 0.06)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final title = _isPatchDropHover ? '松开以添加到清单' : '拖入替换文件或目录';
    final subtitle = hasSpec ? '文件、多个文件、目录都会追加到当前清单' : '首次添加会自动生成清单';

    return DropTarget(
      onDragEntered: (_) => setState(() => _isPatchDropHover = true),
      onDragExited: (_) => setState(() => _isPatchDropHover = false),
      onDragDone: (details) {
        setState(() => _isPatchDropHover = false);
        final paths = [
          for (final file in details.files)
            if (file.path.isNotEmpty) file.path,
        ];
        if (paths.isNotEmpty) {
          widget.onPatchSourcesDropped?.call(paths);
        }
      },
      child: InkWell(
        onTap: widget.onPatchDraftExtend,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: _isPatchDropHover ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isPatchDropHover ? Icons.file_download : Icons.upload_file,
                color: _isPatchDropHover
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _isPatchDropHover
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onPatchDraftExtend,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('选择文件'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatchSpecDisclosure(BuildContext context, String toml) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Text('替换清单', style: TextStyle(fontSize: 13)),
        subtitle: Text('展开查看 TOML 内容', style: _mutedTextStyle(context)),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: SelectableText(
              toml,
              style: const TextStyle(
                fontFamily: 'Sarasa Mono SC',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnresolvedSection(BuildContext context) {
    final entries = widget.unresolvedEntries;
    final colorScheme = Theme.of(context).colorScheme;
    final warningColor = colorScheme.brightness == Brightness.dark
        ? Colors.orange.shade300
        : Colors.orange.shade700;
    return Container(
      decoration: BoxDecoration(
        color: warningColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: warningColor),
                const SizedBox(width: 6),
                Text(
                  '未解析条目 (${entries.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: warningColor,
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
            constraints: const BoxConstraints(maxHeight: 180),
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

  TextStyle _mutedTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.outline,
    );
  }

  int _patchEntryCount(String? toml) {
    if (toml == null) return 0;
    return RegExp(
      r'^\s*\[\[entry\]\]',
      multiLine: true,
    ).allMatches(toml).length;
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
              child: _buildCandidateDropdown(context, entry, chosen),
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

  Widget _buildCandidateDropdown(
    BuildContext context,
    UnresolvedEntry entry,
    String? chosen,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final commonPrefix = _commonPathPrefix(entry.candidates);
    String stripped(String path) =>
        commonPrefix.isNotEmpty ? path.substring(commonPrefix.length) : path;

    final dropdown = DropdownButton<String>(
      value: chosen,
      hint: const Text('选择目标...', style: TextStyle(fontSize: 11)),
      isExpanded: true,
      isDense: true,
      style: TextStyle(
        fontSize: 11,
        fontFamily: 'Sarasa Mono SC',
        color: colorScheme.onSurface,
      ),
      selectedItemBuilder: (context) => entry.candidates.map((c) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(stripped(c), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      items: entry.candidates.map((c) {
        return DropdownMenuItem(
          value: c,
          child: Tooltip(
            message: c,
            child: Text(stripped(c), overflow: TextOverflow.ellipsis),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _resolutions[entry.source] = value);
        }
      },
    );

    if (commonPrefix.isEmpty) return dropdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: commonPrefix,
          child: Text(
            commonPrefix,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Sarasa Mono SC',
              color: Colors.grey.shade600,
            ),
          ),
        ),
        dropdown,
      ],
    );
  }

  // Longest common path-segment prefix across [paths], with a trailing '/'.
  // Always leaves at least one segment per path so dropdown labels are non-empty.
  static String _commonPathPrefix(List<String> paths) {
    if (paths.length < 2) return '';
    final splits = paths.map((p) => p.split('/')).toList();
    final maxCommon = splits
        .map((s) => s.length - 1)
        .reduce((a, b) => a < b ? a : b);
    final common = <String>[];
    for (var i = 0; i < maxCommon; i++) {
      final seg = splits[0][i];
      if (!splits.every((s) => s[i] == seg)) break;
      common.add(seg);
    }
    return common.isEmpty ? '' : '${common.join('/')}/';
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
