import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/zipr_service.dart';
import '../../src/rust/api/zipr_api.dart';
import 'widgets/archive_tree_panel.dart';
import 'widgets/detail_panel.dart';
import 'widgets/diff_tree_panel.dart';

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
  List<UnresolvedEntry> _unresolvedEntries = [];
  bool _isDragging = false;
  StreamSubscription<FileSystemEvent>? _fileWatcher;

  static const _archiveExtensions = ['.zip', '.jar', '.war', '.ear'];

  bool _isValidArchiveFile(String path) {
    final lower = path.toLowerCase();
    return _archiveExtensions.any((ext) => lower.endsWith(ext));
  }

  @override
  void dispose() {
    _disposeFileWatcher();
    super.dispose();
  }

  void _disposeFileWatcher() {
    _fileWatcher?.cancel();
    _fileWatcher = null;
  }

  void _setupFileWatcher(String specPath) {
    _disposeFileWatcher();
    final file = File(specPath);
    _fileWatcher = file.watch(events: FileSystemEvent.modify).listen((_) {
      _reloadSpec();
    });
  }

  Future<void> _reloadSpec() async {
    if (_patchSpecPath == null || !mounted) return;
    final service = context.read<ZiprService>();
    final summary = await service.readPatchSpec(_patchSpecPath!);
    if (summary != null && mounted) {
      setState(() {
        _patchSpecToml = summary.specToml;
        _unresolvedEntries = summary.unresolvedEntries;
      });
    }
  }

  Future<void> _openArchiveFromPath(String path) async {
    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.listArchive(path);
    _disposeFileWatcher();
    setState(() {
      _selectedEntry = null;
      _detailMode = DetailMode.entry;
      _patchSpecToml = null;
      _patchSpecPath = null;
      _unresolvedEntries = [];
    });
  }

  Future<void> _openArchive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'war', 'ear'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    await _openArchiveFromPath(path);
  }

  Future<void> _diffArchives() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要对比的两个归档文件（按住 Ctrl/Cmd 多选）',
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'war', 'ear'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    String leftPath;
    String rightPath;

    if (result.files.length >= 2) {
      leftPath = result.files[0].path!;
      rightPath = result.files[1].path!;
    } else {
      leftPath = result.files.first.path!;
      final second = await FilePicker.platform.pickFiles(
        dialogTitle: '已选择左侧文件，请选择右侧归档文件',
        type: FileType.custom,
        allowedExtensions: ['zip', 'jar', 'war', 'ear'],
      );
      if (second == null || second.files.single.path == null) return;
      rightPath = second.files.single.path!;
    }

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.diffArchives(leftPath, rightPath);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已提取到: $outputPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('提取失败: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('替换失败: ${service.error}')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: ${service.error}')));
    }
  }

  Future<void> _patchDraft() async {
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    final fromDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择补丁源文件目录',
    );
    if (fromDir == null) return;

    await _patchDraftFromDir(fromDir);
  }

  Future<void> _patchDraftFromDir(String fromDir) async {
    if (!mounted) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    try {
      final specPath = '$fromDir/patch.draft.toml';
      final summary = await service.patchDraft(
        service.currentArchivePath!,
        fromDir,
        specPath,
      );
      // Backup original spec
      final origPath = '$fromDir/patch.draft.orig.toml';
      await File(specPath).copy(origPath);

      _setupFileWatcher(specPath);
      setState(() {
        _detailMode = DetailMode.patch;
        _patchSpecToml = summary.specToml;
        _patchSpecPath = specPath;
        _unresolvedEntries = summary.unresolvedEntries;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成清单失败: $e')));
      }
    }
  }

  Future<void> _patchDryRun() async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    final summary = await service.patchApply(
      service.currentArchivePath!,
      _patchSpecPath!,
      dryRun: true,
    );
    if (mounted && summary != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预演结果: 替换=${summary.replaced}, 删除=${summary.deleted}'),
        ),
      );
    }
  }

  Future<void> _patchApply() async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    final summary = await service.patchApply(
      service.currentArchivePath!,
      _patchSpecPath!,
    );
    if (mounted && summary != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已应用: 替换=${summary.replaced}, 删除=${summary.deleted}'),
        ),
      );
    }
  }

  Future<void> _patchResolve(List<Resolution> resolutions) async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    final summary = await service.patchResolve(_patchSpecPath!, resolutions);
    if (summary != null && mounted) {
      setState(() {
        _patchSpecToml = summary.specToml;
        _unresolvedEntries = summary.unresolvedEntries;
      });
    }
  }

  Future<void> _openInEditor() async {
    if (_patchSpecPath == null) return;
    if (Platform.isMacOS) {
      await Process.run('open', [_patchSpecPath!]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', _patchSpecPath!]);
    } else {
      await Process.run('xdg-open', [_patchSpecPath!]);
    }
  }

  Future<void> _restoreOriginal() async {
    if (_patchSpecPath == null) return;
    final origPath = _patchSpecPath!.replaceAll(
      '.draft.toml',
      '.draft.orig.toml',
    );
    final origFile = File(origPath);
    if (!await origFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到原始清单备份')));
      }
      return;
    }
    await origFile.copy(_patchSpecPath!);
    await _reloadSpec();
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
          child: DropTarget(
            onDragEntered: (_) => setState(() => _isDragging = true),
            onDragExited: (_) => setState(() => _isDragging = false),
            onDragDone: (details) {
              setState(() => _isDragging = false);
              if (details.files.isEmpty) return;
              final path = details.files.first.path;
              if (Directory(path).existsSync()) {
                final service = context.read<ZiprService>();
                if (service.currentArchivePath != null) {
                  _patchDraftFromDir(path);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('请先打开归档文件，再拖入目录进行批量替换'),
                    ),
                  );
                }
              } else if (_isValidArchiveFile(path)) {
                _openArchiveFromPath(path);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('不支持的文件格式，请拖入 zip/jar/war/ear 文件或目录'),
                  ),
                );
              }
            },
            child: service.loading
                ? const Center(child: CircularProgressIndicator())
                : service.currentArchivePath == null &&
                      service.diffEntries.isEmpty
                ? Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isDragging
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                        color: _isDragging
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.05)
                            : null,
                      ),
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isDragging
                                ? Icons.file_download
                                : Icons.inventory_2_outlined,
                            size: 64,
                            color: _isDragging
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isDragging ? '松开以打开归档文件' : '选择或拖入归档文件开始操作',
                            style: TextStyle(
                              color: _isDragging
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _detailMode == DetailMode.diff &&
                      service.diffEntries.isNotEmpty
                    ? Stack(
                        children: [
                          DiffTreePanel(
                            diffEntries: service.diffEntries,
                            leftPath: service.diffLeftPath ?? '',
                            rightPath: service.diffRightPath ?? '',
                            onClose: () {
                              service.clearDiff();
                              setState(() => _detailMode = DetailMode.entry);
                            },
                          ),
                          if (_isDragging)
                            Positioned.fill(
                              child: Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.08),
                                child: Center(
                                  child: Text(
                                    '松开以切换归档文件',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Stack(
                        children: [
                          Row(
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
                                  unresolvedEntries: _unresolvedEntries,
                                  onPatchDraft: _patchDraft,
                                  onPatchDryRun: _patchDryRun,
                                  onPatchApply: _patchApply,
                                  onOpenInEditor: _openInEditor,
                                  onReload: _reloadSpec,
                                  onRestoreOriginal: _restoreOriginal,
                                  onResolve: _patchResolve,
                                ),
                              ),
                            ],
                          ),
                          if (_isDragging)
                            Positioned.fill(
                              child: Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.08),
                                child: Center(
                                  child: Text(
                                    '松开以切换归档文件',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
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
