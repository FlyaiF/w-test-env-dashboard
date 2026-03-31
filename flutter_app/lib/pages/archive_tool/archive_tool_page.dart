import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/zipr_service.dart';
import '../../src/rust/api/zipr_api.dart';
import 'widgets/archive_tree_panel.dart';
import 'widgets/detail_panel.dart';

class ArchiveToolPage extends StatefulWidget {
  const ArchiveToolPage({super.key});

  @override
  State<ArchiveToolPage> createState() => _ArchiveToolPageState();
}

class _ArchiveToolPageState extends State<ArchiveToolPage> {
  ArchiveEntry? _selectedEntry;
  DetailMode _detailMode = DetailMode.entry;
  String? _patchSpecToml;
  String? _patchSpecPath;

  Future<void> _openArchive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'war', 'ear'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.listArchive(path);
    setState(() {
      _selectedEntry = null;
      _detailMode = DetailMode.entry;
      _patchSpecToml = null;
      _patchSpecPath = null;
    });
  }

  Future<void> _diffArchives() async {
    final left = await FilePicker.platform.pickFiles(
      dialogTitle: '选择左侧归档文件',
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'war', 'ear'],
    );
    if (left == null || left.files.single.path == null) return;

    final right = await FilePicker.platform.pickFiles(
      dialogTitle: '选择右侧归档文件',
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'war', 'ear'],
    );
    if (right == null || right.files.single.path == null) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.diffArchives(
      left.files.single.path!,
      right.files.single.path!,
    );
    setState(() => _detailMode = DetailMode.diff);
  }

  Future<void> _extractEntry(String zipExpr) async {
    final name = zipExpr.split('/').last.split('!').first;
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '保存提取的文件',
      fileName: name,
    );
    if (outputPath == null) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    try {
      await service.extractEntry(zipExpr, outputPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已提取到: $outputPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取失败: $e')),
        );
      }
    }
  }

  Future<void> _replaceEntry(String zipExpr) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.replaceEntry(zipExpr, result.files.single.path!);
    if (mounted && service.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('替换失败: ${service.error}')),
      );
    }
  }

  Future<void> _deleteEntry(String zipExpr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 $zipExpr 吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.deleteEntry(zipExpr);
    if (mounted && service.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: ${service.error}')),
      );
    }
  }

  Future<void> _patchDraft() async {
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    final fromDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择补丁源文件目录',
    );
    if (fromDir == null) return;

    if (!mounted) return;
    try {
      final summary = await service.patchDraft(
        service.currentArchivePath!,
        fromDir,
        '$fromDir/patch.draft.toml',
      );
      setState(() {
        _detailMode = DetailMode.patch;
        _patchSpecToml = summary.specToml;
        _patchSpecPath = '$fromDir/patch.draft.toml';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成清单失败: $e')),
        );
      }
    }
  }

  Future<void> _patchDryRun() async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    try {
      final summary = await service.patchApply(
        service.currentArchivePath!,
        _patchSpecPath!,
        dryRun: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '预演结果: 替换=${summary.replaced}, 删除=${summary.deleted}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('预演失败: $e')),
        );
      }
    }
  }

  Future<void> _patchApply() async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    try {
      final summary = await service.patchApply(
        service.currentArchivePath!,
        _patchSpecPath!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已应用: 替换=${summary.replaced}, 删除=${summary.deleted}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('应用失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ZiprService>();

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text('归档工具', style: Theme.of(context).textTheme.titleLarge),
              if (service.currentArchivePath != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    service.currentArchivePath!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              FilledButton.icon(
                onPressed: _openArchive,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开归档文件'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _diffArchives,
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('对比归档'),
              ),
              if (service.currentArchivePath != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _detailMode = DetailMode.patch);
                  },
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('批量替换'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: service.loading
              ? const Center(child: CircularProgressIndicator())
              : service.currentArchivePath == null &&
                      service.diffEntries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '选择归档文件开始操作',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ArchiveTreePanel(
                            entries: service.entries,
                            onEntrySelected: (entry) {
                              setState(() {
                                _selectedEntry = entry;
                                _detailMode = DetailMode.entry;
                              });
                            },
                            onExtract: _extractEntry,
                            onReplace: _replaceEntry,
                            onDelete: _deleteEntry,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 2,
                          child: DetailPanel(
                            mode: _detailMode,
                            selectedEntry: _selectedEntry,
                            diffEntries: service.diffEntries,
                            patchSpecToml: _patchSpecToml,
                            onPatchDraft: _patchDraft,
                            onPatchDryRun: _patchDryRun,
                            onPatchApply: _patchApply,
                          ),
                        ),
                      ],
                    ),
        ),
        // Error bar
        if (service.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: service.clearError,
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
