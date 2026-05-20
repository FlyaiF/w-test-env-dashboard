import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/zipr_service.dart';
import '../../src/rust/api/zipr_api.dart';
import 'local_draft_extender.dart';
import 'widgets/archive_tree_panel.dart';
import 'widgets/detail_panel.dart';
import 'widgets/diff_tree_panel.dart';

class ArchiveToolPage extends StatefulWidget {
  final VoidCallback? onAbout;

  const ArchiveToolPage({super.key, this.onAbout});

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
  bool _isPickingPatchSources = false;
  StreamSubscription<FileSystemEvent>? _fileWatcher;
  // Set by local Dart-side spec writes so the watcher's reload doesn't bounce
  // back into Rust just to re-read what we already have in memory.
  bool _suppressNextWatcherReload = false;

  static const _archiveExtensions = ['.zip', '.jar', '.war', '.ear'];

  bool _isValidArchiveFile(String path) {
    final lower = path.toLowerCase();
    return _archiveExtensions.any((ext) => lower.endsWith(ext));
  }

  String _dragOverlayLabel(ZiprService service) {
    if (service.currentArchivePath == null) return '松开以打开归档文件';
    if (_detailMode == DetailMode.patch || _patchSpecPath != null) {
      return '松开以添加到批量替换';
    }
    return '松开以添加替换文件或打开归档';
  }

  Widget _buildDragOverlay(BuildContext context, ZiprService service) {
    return Positioned.fill(
      child: Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        child: Center(
          child: Text(
            _dragOverlayLabel(service),
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperationStatus(BuildContext context, ZiprService service) {
    final message = service.operationMessage;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView(BuildContext context, ZiprService service) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                service.operationMessage ?? '处理中...',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      if (_suppressNextWatcherReload) {
        _suppressNextWatcherReload = false;
        return;
      }
      _reloadSpec();
    });
  }

  Future<void> _reloadSpec() async {
    if (_patchSpecPath == null || !mounted) return;
    await _sanitizePatchSpecForUnresolvedTables();
    if (!mounted) return;
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
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认替换'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作会直接修改当前归档文件。建议在替换前确认已有备份。'),
            const SizedBox(height: 12),
            _confirmRow('目标条目', zipExpr),
            _confirmRow('源文件', sourcePath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final service = context.read<ZiprService>();
    await service.replaceEntry(zipExpr, sourcePath);
    if (!mounted) return;
    final message = service.error == null
        ? '已用 ${_basename(sourcePath)} 替换目标条目'
        : '替换失败: ${service.error}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  void _showArchiveActionError(String prefix, ZiprService service) {
    if (service.error == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$prefix: ${service.error}')));
  }

  void _showPatchSummary(
    String successPrefix,
    String failurePrefix,
    ApplySummary? summary,
    ZiprService service,
  ) {
    if (summary == null) {
      _showArchiveActionError(failurePrefix, service);
      return;
    }
    final backup = summary.backupPath;
    final elapsed = service.lastPatchApplyDuration;
    final lines = <String>[
      '$successPrefix: 替换=${summary.replaced}, 删除=${summary.deleted}',
      if (elapsed != null) '耗时: ${_formatDuration(elapsed)}',
      if (backup != null && backup.isNotEmpty) '已备份: $backup（可点击"回滚"撤销）',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lines.join('\n')),
        duration: backup != null
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds >= 1) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(2)} 秒';
    }
    return '${duration.inMilliseconds} 毫秒';
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

  void _discardPatchDraft() {
    _disposeFileWatcher();
    setState(() {
      _patchSpecToml = null;
      _patchSpecPath = null;
      _unresolvedEntries = [];
      _suppressNextWatcherReload = false;
      _detailMode = DetailMode.patch;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已丢弃当前替换清单')));
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
    if (mounted) {
      _showPatchSummary('预演结果', '预演失败', summary, service);
    }
  }

  Future<void> _patchApply() async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    final archive = service.currentArchivePath;
    if (archive == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认应用替换'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作会直接修改归档文件。应用前会先在同目录写入一个 .bak- 时间戳备份，可随后点击"回滚"撤销。'),
            const SizedBox(height: 12),
            _confirmRow('归档', archive),
            _confirmRow('清单', _patchSpecPath!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.bolt),
            label: const Text('确认应用'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final summary = await service.patchApply(archive, _patchSpecPath!);
    if (mounted) {
      _showPatchSummary('已应用', '应用失败', summary, service);
    }
  }

  Future<void> _patchDraftExtend() async {
    if (_isPickingPatchSources) return;
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null) return;

    _isPickingPatchSources = true;
    try {
      final fileResult = await FilePicker.platform.pickFiles(
        dialogTitle: '选择要追加到清单的文件',
        allowMultiple: true,
      );
      if (fileResult == null || fileResult.files.isEmpty) return;

      final List<String> sources = [];
      for (final f in fileResult.files) {
        if (f.path != null) sources.add(f.path!);
      }
      if (sources.isEmpty) return;
      await _handlePatchSources(sources);
    } finally {
      _isPickingPatchSources = false;
    }
  }

  Future<void> _handlePatchSources(List<String> sources) async {
    final service = context.read<ZiprService>();
    if (service.currentArchivePath == null || sources.isEmpty) return;

    if (_patchSpecPath != null) {
      await _extendDraftLocally(sources);
      return;
    }

    if (sources.length == 1 && Directory(sources.single).existsSync()) {
      await _patchDraftFromDir(sources.single);
      return;
    }

    await _createLocalDraftFromSources(sources);
  }

  Future<void> _createLocalDraftFromSources(List<String> sources) async {
    if (!mounted) return;
    final service = context.read<ZiprService>();
    final archive = service.currentArchivePath;
    if (archive == null || sources.isEmpty) return;

    final specDir = await _specDirectoryForSources(sources);
    if (specDir == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到可写入清单的位置')));
      return;
    }

    final specPath = '${specDir.path}${Platform.pathSeparator}patch.draft.toml';
    final header = StringBuffer()
      ..writeln('version = 1')
      ..writeln('archive = ${_toml(archive.replaceAll('\\', '/'))}')
      ..writeln(
        'generated_at = ${_toml(DateTime.now().toUtc().toIso8601String())}',
      );
    await File(specPath).writeAsString(header.toString(), flush: true);

    _setupFileWatcher(specPath);
    setState(() {
      _detailMode = DetailMode.patch;
      _patchSpecToml = header.toString();
      _patchSpecPath = specPath;
      _unresolvedEntries = [];
    });

    await _extendDraftLocally(sources);
    if (_patchSpecPath == null) return;
    final origPath = _patchSpecPath!.replaceAll(
      '.draft.toml',
      '.draft.orig.toml',
    );
    await File(_patchSpecPath!).copy(origPath);
  }

  Future<Directory?> _specDirectoryForSources(List<String> sources) async {
    for (final source in sources) {
      final type = await FileSystemEntity.type(source);
      if (type == FileSystemEntityType.directory) {
        return Directory(source);
      }
      if (type == FileSystemEntityType.file) {
        return File(source).parent;
      }
    }
    return null;
  }

  /// Match new sources against the cached archive path list and append the
  /// resulting entries directly to the on-disk TOML — no FFI round-trip.
  Future<void> _extendDraftLocally(List<String> sources) async {
    if (_patchSpecPath == null) return;
    final service = context.read<ZiprService>();
    final messenger = ScaffoldMessenger.of(context);

    // Make sure the path cache is populated. Cheap if already loaded.
    if (service.allArchivePaths == null) {
      await service.loadAllArchivePaths();
    }
    final paths = service.allArchivePaths;
    if (paths == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('归档路径缓存未就绪: ${service.error ?? ""}')),
      );
      return;
    }

    final existingSources = _extractExistingSources(_patchSpecToml ?? '');
    _suppressNextWatcherReload = true;
    final LocalExtendResult result;
    try {
      result = await LocalDraftExtender.extend(
        specPath: _patchSpecPath!,
        sourceRoots: sources,
        allArchivePaths: paths,
        existingSources: existingSources,
      );
    } catch (e) {
      _suppressNextWatcherReload = false;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('本地追加失败: $e')));
      return;
    }

    // Mirror the on-disk append in our in-memory state so we don't bounce
    // back into Rust just to re-parse the spec.
    final appended = _renderAppendedToml(result);
    final newToml = LocalDraftExtender.sanitizeUnresolvedTables(
      (_patchSpecToml ?? '') + appended,
    );
    final mergedUnresolved = [..._unresolvedEntries, ...result.newUnresolved];
    if (!mounted) return;
    setState(() {
      _patchSpecToml = newToml;
      _unresolvedEntries = mergedUnresolved;
    });

    final parts = <String>[
      '已追加: 匹配=${result.newEntries.length}, 未解析=${result.newUnresolved.length}',
    ];
    if (result.skippedDuplicates > 0) {
      parts.add('跳过重复=${result.skippedDuplicates}');
    }
    messenger.showSnackBar(SnackBar(content: Text(parts.join('，'))));
  }

  Set<String> _extractExistingSources(String toml) {
    final sources = <String>{};
    final re = RegExp(
      r'^\s*source\s*=\s*"((?:\\.|[^"\\])*)"\s*$',
      multiLine: true,
    );
    for (final m in re.allMatches(toml)) {
      final raw = m.group(1)!;
      sources.add(raw.replaceAll(r'\\', r'\').replaceAll(r'\"', '"'));
    }
    return sources;
  }

  String _renderAppendedToml(LocalExtendResult result) {
    final buf = StringBuffer();
    for (final e in result.newEntries) {
      buf
        ..writeln()
        ..writeln('[[entry]]')
        ..writeln('target = ${_toml(e.target)}')
        ..writeln('source = ${_toml(e.source)}')
        ..writeln('action = "replace"')
        ..writeln('method = "inherit"')
        ..writeln('level = "inherit"')
        ..writeln('mtime = "source"')
        ..writeln('comment = "inherit"');
    }
    for (final u in result.newUnresolved) {
      buf
        ..writeln()
        ..writeln('[[unresolved]]')
        ..writeln('source = ${_toml(u.source)}')
        ..writeln('reason = ${_toml(u.reason)}')
        ..writeln('candidates = [${u.candidates.map(_toml).join(', ')}]');
    }
    return buf.toString();
  }

  String _toml(String s) {
    final esc = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$esc"';
  }

  Future<void> _rollbackArchive() async {
    final service = context.read<ZiprService>();
    final archive = service.currentArchivePath;
    final backup = service.lastBackupPath;
    if (archive == null || backup == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('回滚归档到上次备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作会用备份覆盖当前归档，备份文件随后被移除。'),
            const SizedBox(height: 12),
            _confirmRow('归档', archive),
            _confirmRow('备份', backup),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.undo),
            label: const Text('确认回滚'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await service.restoreArchiveBackup(archive, backup);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已回滚到备份状态' : '回滚失败: ${service.error ?? ""}')),
    );
  }

  Future<void> _patchResolve(List<Resolution> resolutions) async {
    if (_patchSpecPath == null) return;
    await _sanitizePatchSpecForUnresolvedTables();
    if (!mounted) return;
    final service = context.read<ZiprService>();
    final summary = await service.patchResolve(_patchSpecPath!, resolutions);
    if (summary != null && mounted) {
      setState(() {
        _patchSpecToml = summary.specToml;
        _unresolvedEntries = summary.unresolvedEntries;
      });
    }
  }

  Future<void> _sanitizePatchSpecForUnresolvedTables() async {
    final specPath = _patchSpecPath;
    if (specPath == null) return;
    final file = File(specPath);
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    final sanitized = LocalDraftExtender.sanitizeUnresolvedTables(raw);
    if (sanitized == raw) return;
    _suppressNextWatcherReload = true;
    await file.writeAsString(sanitized, flush: true);
    if (!mounted) return;
    setState(() => _patchSpecToml = sanitized);
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

  Widget _buildPatchPage(BuildContext context, ZiprService service) {
    return Stack(
      children: [
        DetailPanel(
          mode: DetailMode.patch,
          patchSpecToml: _patchSpecToml,
          unresolvedEntries: _unresolvedEntries,
          onPatchDraftExtend: _patchDraftExtend,
          onPatchDiscard: _discardPatchDraft,
          onPatchSourcesDropped: _handlePatchSources,
          onPatchDryRun: _patchDryRun,
          onPatchApply: _patchApply,
          onOpenInEditor: _openInEditor,
          onReload: _reloadSpec,
          onRestoreOriginal: _restoreOriginal,
          onRollbackArchive: _rollbackArchive,
          canRollback: service.lastBackupPath != null,
          onResolve: _patchResolve,
          onClose: () => setState(() => _detailMode = DetailMode.entry),
        ),
        if (_isDragging) _buildDragOverlay(context, service),
      ],
    );
  }

  Widget _buildBrowsePage(BuildContext context, ZiprService service) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ArchiveTreePanel(
                entries: service.entries,
                expandingArchives: service.expandingArchivesView,
                onEntrySelected: (entry) {
                  setState(() {
                    _selectedEntry = entry;
                    _detailMode = DetailMode.entry;
                  });
                },
                onExtract: _extractEntry,
                onReplace: _replaceEntry,
                onDelete: _deleteEntry,
                onExpandArchive: (zipExpr) {
                  service.expandArchive(zipExpr);
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 2,
              child: DetailPanel(
                mode: DetailMode.entry,
                selectedEntry: _selectedEntry,
                diffEntries: service.diffEntries,
              ),
            ),
          ],
        ),
        if (_isDragging) _buildDragOverlay(context, service),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ZiprService>();

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('归档工具', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (widget.onAbout != null) ...[
                    IconButton(
                      onPressed: widget.onAbout,
                      icon: const Icon(Icons.info_outline, size: 20),
                      tooltip: '关于',
                    ),
                    const SizedBox(width: 4),
                  ],
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
              if (service.currentArchivePath != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
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
                  ],
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
              final paths = [
                for (final file in details.files)
                  if (file.path.isNotEmpty) file.path,
              ];
              if (paths.isEmpty) return;
              final service = context.read<ZiprService>();
              if (service.currentArchivePath != null &&
                  _detailMode == DetailMode.patch) {
                _handlePatchSources(paths);
                return;
              }
              final path = paths.first;
              if (Directory(path).existsSync()) {
                if (service.currentArchivePath == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请先打开归档文件，再拖入目录进行批量替换')),
                  );
                } else if (_patchSpecPath != null) {
                  // Draft already exists — append locally rather than overwrite.
                  _handlePatchSources(paths);
                } else {
                  _patchDraftFromDir(path);
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
                ? _buildLoadingView(context, service)
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
                      if (_isDragging && _detailMode != DetailMode.patch)
                        _buildDragOverlay(context, service),
                    ],
                  )
                : _detailMode == DetailMode.patch
                ? _buildPatchPage(context, service)
                : _buildBrowsePage(context, service),
          ),
        ),
        if (service.operationMessage != null && !service.loading)
          _buildOperationStatus(context, service),
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
