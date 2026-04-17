import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../config/feature_profile.dart';
import '../../sidecar/sidecar_client.dart';
import '../../sidecar/sidecar_manager.dart';

const String _appCommit = String.fromEnvironment('COMMIT', defaultValue: 'dev');
const String _appBuildTime =
    String.fromEnvironment('BUILD_TIME', defaultValue: 'unknown');

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;
  Map<String, dynamic>? _sidecarVersion;
  String? _sidecarError;
  bool _fetchedForBaseUrl = false;
  String? _lastBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  Future<void> _fetchSidecarVersion(SidecarManager sidecar) async {
    if (!sidecar.connected || sidecar.port == null) return;
    final baseUrl = sidecar.baseUrl;
    if (_fetchedForBaseUrl && _lastBaseUrl == baseUrl) return;
    _fetchedForBaseUrl = true;
    _lastBaseUrl = baseUrl;
    try {
      final data = await SidecarClient(baseUrl).getVersion();
      if (!mounted) return;
      setState(() {
        _sidecarVersion = data;
        _sidecarError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sidecarError = e.toString());
    }
  }

  String _buildPlainText(
    SidecarManager sidecar,
    FeatureProfile profile,
  ) {
    final buf = StringBuffer();
    buf.writeln('=== 应用版本 ===');
    buf.writeln('version: ${_packageInfo?.version ?? '-'}+'
        '${_packageInfo?.buildNumber ?? '-'}');
    buf.writeln('commit: $_appCommit');
    buf.writeln('buildTime: $_appBuildTime');
    buf.writeln();
    buf.writeln('=== 后端服务 ===');
    if (!sidecar.connected) {
      buf.writeln('status: 未连接');
    } else if (_sidecarVersion != null) {
      _sidecarVersion!.forEach((k, v) => buf.writeln('$k: $v'));
    } else if (_sidecarError != null) {
      buf.writeln('error: $_sidecarError');
    } else {
      buf.writeln('status: 加载中');
    }
    buf.writeln();
    buf.writeln('=== 运行环境 ===');
    buf.writeln('os: ${Platform.operatingSystem}');
    buf.writeln('osVersion: ${Platform.operatingSystemVersion}');
    buf.writeln('dart: ${Platform.version}');
    buf.writeln('executable: ${Platform.resolvedExecutable}');
    buf.writeln();
    buf.writeln('=== 功能配置 ===');
    buf.writeln('namedProfile: ${profile.isNamedProfile}');
    buf.writeln(
        'features: ${profile.enabledFeatures.map((f) => f.name).join(', ')}');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final sidecar = context.watch<SidecarManager>();
    final profile = context.watch<FeatureProfile>();
    _fetchSidecarVersion(sidecar);

    final theme = Theme.of(context);
    final info = _packageInfo;
    final flutterVersion = info == null
        ? '加载中...'
        : '${info.version}+${info.buildNumber}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('关于', style: theme.textTheme.headlineSmall),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制全部信息'),
                onPressed: () async {
                  final text = _buildPlainText(sidecar, profile);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: '应用版本',
                    rows: [
                      _Row('版本号', flutterVersion),
                      _Row('Commit', _appCommit),
                      _Row('构建时间', _appBuildTime),
                      if (info != null) _Row('包名', info.packageName),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: '后端服务',
                    rows: _sidecarRows(sidecar),
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: '运行环境',
                    rows: [
                      _Row('操作系统', Platform.operatingSystem),
                      _Row('系统版本', Platform.operatingSystemVersion),
                      _Row('Dart', Platform.version),
                      _Row('可执行文件', Platform.resolvedExecutable),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: '功能配置',
                    rows: [
                      _Row('命名配置', profile.isNamedProfile ? '是' : '否'),
                      _Row('已启用功能',
                          profile.enabledFeatures.map((f) => f.name).join(', ')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_Row> _sidecarRows(SidecarManager sidecar) {
    if (!sidecar.connected) {
      return [const _Row('状态', '未连接')];
    }
    final v = _sidecarVersion;
    if (v == null) {
      if (_sidecarError != null) {
        return [_Row('错误', _sidecarError!)];
      }
      return [const _Row('状态', '加载中...')];
    }
    return [
      _Row('版本号', v['version']?.toString() ?? '-'),
      _Row('Commit', v['commit']?.toString() ?? '-'),
      _Row('构建时间', v['buildTime']?.toString() ?? '-'),
      _Row('Go 版本', v['goVersion']?.toString() ?? '-'),
      _Row('平台', v['platform']?.toString() ?? '-'),
      _Row('监听地址', sidecar.baseUrl),
    ];
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        row.label,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        row.value,
                        style: const TextStyle(
                          fontFamily: 'Sarasa Mono SC',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
