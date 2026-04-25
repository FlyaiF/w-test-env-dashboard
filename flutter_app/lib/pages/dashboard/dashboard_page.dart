import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../models/env_info.dart';
import '../../services/env_service.dart';
import '../../widgets/filter_history_text_field.dart';

class DashboardPage extends StatefulWidget {
  final void Function(EnvInfo env)? onViewLog;

  const DashboardPage({super.key, this.onViewLog});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _searchController = TextEditingController();
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnvService>().load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EnvService>();

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('环境总览', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 16),
              Text(
                '共 ${service.total} 条',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const Spacer(),
              SizedBox(
                width: 300,
                child: FilterHistoryTextField(
                  controller: _searchController,
                  filterText: _searchController.text,
                  hintText: '搜索环境名称、地址、备注、版本...',
                  onChanged: (v) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      service.setSearch(v);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: service.syncing ? null : service.sync,
                tooltip: '从远程刷新',
              ),
            ],
          ),
        ),
        // Error banner
        if (service.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red.shade50,
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(onPressed: service.load, child: const Text('重试')),
              ],
            ),
          ),
        // Loading
        if (service.loading || service.syncing) const LinearProgressIndicator(),
        // Card list
        Expanded(
          child: service.envs.isEmpty && !service.loading
              ? const Center(
                  child: Text('暂无数据', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  itemCount: service.envs.length,
                  itemBuilder: (context, index) =>
                      _buildCard(service.envs[index]),
                ),
        ),
        // Pagination
        if (service.total > service.pageSize)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: service.page > 1
                      ? () => service.setPage(service.page - 1)
                      : null,
                ),
                Text(
                  '第 ${service.page} 页 / 共 ${(service.total / service.pageSize).ceil()} 页',
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      service.page < (service.total / service.pageSize).ceil()
                      ? () => service.setPage(service.page + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCard(EnvInfo e) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: number badge + name + actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${e.eNo}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.eName ?? '-',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (e.eWeblogpath != null && e.eWebserveraddr != null)
                  IconButton(
                    icon: const Icon(Icons.article, size: 18),
                    tooltip: '查看日志',
                    onPressed: () => widget.onViewLog?.call(e),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                if (e.eSeeurl != null)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: 'SEE平台',
                    onPressed: () => _launchUrl(e.eSeeurl!),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  tooltip: '详情',
                  onPressed: () => _showDetail(e),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            // URL row
            if (e.eUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: InkWell(
                        onTap: () => _launchUrl(e.eUrl!),
                        child: Text(
                          e.eUrl!,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      tooltip: '复制地址',
                      onPressed: () => _copyToClipboard(e.eUrl!, '访问地址'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ),
            // Version + time row
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.label_outline,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      e.eVersion ?? '-',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (e.eVersion != null)
                    IconButton(
                      icon: Icon(
                        Icons.copy,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      tooltip: '复制版本号',
                      onPressed: () => _copyToClipboard(e.eVersion!, '版本号'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    e.eUpdatetime != null
                        ? _dateFmt.format(e.eUpdatetime!.toLocal())
                        : '-',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // Memo row
            if (e.eMemo != null && e.eMemo!.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.notes, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.eMemo!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showDetail(EnvInfo e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.eName ?? '环境 #${e.eNo}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                _detailRow('编号', '${e.eNo}'),
                _detailRow('环境别名', e.eName),
                _detailRow('业务库', e.eYwdb),
                _detailRow('中间库', e.eZjdb),
                _detailRow('访问地址', e.eUrl),
                _detailRow('版本号', e.eVersion),
                _detailRow(
                  '更新时间',
                  e.eUpdatetime != null
                      ? _dateFmt.format(e.eUpdatetime!.toLocal())
                      : null,
                ),
                _detailRow('SEE平台', e.eSeeurl),
                _detailRow('Web服务地址', e.eWebserveraddr),
                _detailRow('Web日志路径', e.eWeblogpath),
                _detailRow('备注', e.eMemo),
                _detailRow('数据库类型', e.eDbtype),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  TableRow _detailRow(String label, String? value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: SelectableText(value ?? '-'),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    var uri = Uri.tryParse(url);
    if (uri != null && !uri.hasScheme) {
      uri = Uri.parse('http://$url');
    }
    if (uri != null) {
      await launchUrl(uri);
    }
  }
}
