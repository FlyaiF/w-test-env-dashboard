import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../api/backend_client.dart';
import '../../catalog/environment_store.dart';

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

  String _backendStatus(EnvironmentStore store) {
    if (store.connected) return '已连接';
    if (store.loading) return '连接中...';
    return '未连接';
  }

  String _buildPlainText(EnvironmentStore store, String baseUrl) {
    final buf = StringBuffer();
    buf.writeln('=== 应用版本 ===');
    buf.writeln('version: ${_packageInfo?.version ?? '-'}+'
        '${_packageInfo?.buildNumber ?? '-'}');
    buf.writeln('commit: $_appCommit');
    buf.writeln('buildTime: $_appBuildTime');
    buf.writeln();
    buf.writeln('=== 后端服务 ===');
    buf.writeln('status: ${_backendStatus(store)}');
    buf.writeln('baseUrl: $baseUrl');
    if (store.error != null) {
      buf.writeln('error: ${store.error}');
    }
    buf.writeln();
    buf.writeln('=== 运行环境 ===');
    buf.writeln('os: ${Platform.operatingSystem}');
    buf.writeln('osVersion: ${Platform.operatingSystemVersion}');
    buf.writeln('dart: ${Platform.version}');
    buf.writeln('executable: ${Platform.resolvedExecutable}');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EnvironmentStore>();
    final baseUrl = context.read<BackendClient>().baseUrl;

    final theme = Theme.of(context);
    final info = _packageInfo;
    final appVersion = info == null
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
                  final text = _buildPlainText(store, baseUrl);
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
                  Section(
                    title: '应用版本',
                    rows: [
                      LabelValueRow('版本号', appVersion),
                      const LabelValueRow('Commit', _appCommit),
                      const LabelValueRow('构建时间', _appBuildTime),
                      if (info != null) LabelValueRow('包名', info.packageName),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: '后端服务',
                    rows: [
                      LabelValueRow('状态', _backendStatus(store)),
                      LabelValueRow('服务地址', baseUrl),
                      if (store.error != null)
                        LabelValueRow('错误', store.error!),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Section(
                    title: '运行环境',
                    rows: [
                      LabelValueRow('操作系统', Platform.operatingSystem),
                      LabelValueRow('系统版本', Platform.operatingSystemVersion),
                      LabelValueRow('Dart', Platform.version),
                      LabelValueRow('可执行文件', Platform.resolvedExecutable),
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
}
