import 'package:flutter/material.dart';

import '../../../src/rust/api/zipr_api.dart';

enum DetailMode { entry, diff, patch }

class DetailPanel extends StatelessWidget {
  final DetailMode mode;
  final ArchiveEntry? selectedEntry;
  final List<DiffEntry> diffEntries;
  final String? patchSpecToml;
  final VoidCallback? onPatchDraft;
  final VoidCallback? onPatchDryRun;
  final VoidCallback? onPatchApply;

  const DetailPanel({
    super.key,
    required this.mode,
    this.selectedEntry,
    this.diffEntries = const [],
    this.patchSpecToml,
    this.onPatchDraft,
    this.onPatchDryRun,
    this.onPatchApply,
  });

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      DetailMode.entry => _buildEntryDetail(context),
      DetailMode.diff => _buildDiffView(context),
      DetailMode.patch => _buildPatchView(context),
    };
  }

  Widget _buildEntryDetail(BuildContext context) {
    if (selectedEntry == null) {
      return const Center(
        child: Text('选择文件查看详情', style: TextStyle(color: Colors.grey)),
      );
    }

    final e = selectedEntry!;
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
    if (diffEntries.isEmpty) {
      return const Center(
        child: Text('无差异', style: TextStyle(color: Colors.grey)),
      );
    }

    final added = diffEntries.where((e) => e.kind == 'added').length;
    final removed = diffEntries.where((e) => e.kind == 'removed').length;
    final modified = diffEntries.where((e) => e.kind == 'modified').length;

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
            itemCount: diffEntries.length,
            itemBuilder: (context, index) {
              final entry = diffEntries[index];
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('批量替换', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onPatchDraft,
                icon: const Icon(Icons.description, size: 18),
                label: const Text('生成清单'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: patchSpecToml != null ? onPatchDryRun : null,
                icon: const Icon(Icons.preview, size: 18),
                label: const Text('预演'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: patchSpecToml != null ? onPatchApply : null,
                child: const Text('应用替换'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (patchSpecToml != null) ...[
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
                    patchSpecToml!,
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
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
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
