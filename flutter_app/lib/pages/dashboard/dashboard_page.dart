import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../models/env_info.dart';
import '../../services/env_service.dart';

class DashboardPage extends StatefulWidget {
  final VoidCallback? onViewLog;

  const DashboardPage({super.key, this.onViewLog});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _searchController = TextEditingController();
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnvService>().load();
    });
  }

  @override
  void dispose() {
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
              Text('共 ${service.total} 条',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              const Spacer(),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索环境名称、地址、备注...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              service.setSearch('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    service.setSearch(v);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: service.load,
                tooltip: '刷新',
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
                Expanded(child: Text(service.error!, style: const TextStyle(color: Colors.red))),
                TextButton(onPressed: service.load, child: const Text('重试')),
              ],
            ),
          ),
        // Loading
        if (service.loading) const LinearProgressIndicator(),
        // Table
        Expanded(
          child: service.envs.isEmpty && !service.loading
              ? const Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 24,
                      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                      columns: const [
                        DataColumn(label: Text('编号')),
                        DataColumn(label: Text('环境别名')),
                        DataColumn(label: Text('访问地址')),
                        DataColumn(label: Text('版本号')),
                        DataColumn(label: Text('更新时间')),
                        DataColumn(label: Text('备注')),
                        DataColumn(label: Text('操作')),
                      ],
                      rows: service.envs.map((e) => _buildRow(e)).toList(),
                    ),
                  ),
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
                  onPressed: service.page > 1 ? () => service.setPage(service.page - 1) : null,
                ),
                Text('第 ${service.page} 页 / 共 ${(service.total / service.pageSize).ceil()} 页'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: service.page < (service.total / service.pageSize).ceil()
                      ? () => service.setPage(service.page + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  DataRow _buildRow(EnvInfo e) {
    return DataRow(
      cells: [
        DataCell(Text('${e.eNo}')),
        DataCell(Text(e.eName ?? '-')),
        DataCell(
          e.eUrl != null
              ? InkWell(
                  onTap: () => _launchUrl(e.eUrl!),
                  child: Text(e.eUrl!, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                )
              : const Text('-'),
        ),
        DataCell(Text(e.eVersion ?? '-')),
        DataCell(Text(e.eUpdatetime != null ? _dateFmt.format(e.eUpdatetime!) : '-')),
        DataCell(Text(e.eMemo ?? '-', overflow: TextOverflow.ellipsis)),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.eWeblogpath != null && e.eWebserveraddr != null)
              IconButton(
                icon: const Icon(Icons.article, size: 18),
                tooltip: '查看日志',
                onPressed: widget.onViewLog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (e.eSeeurl != null)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: 'SEE平台',
                onPressed: () => _launchUrl(e.eSeeurl!),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              tooltip: '详情',
              onPressed: () => _showDetail(e),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        )),
      ],
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
              columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                _detailRow('编号', '${e.eNo}'),
                _detailRow('环境别名', e.eName),
                _detailRow('业务库', e.eYwdb),
                _detailRow('中间库', e.eZjdb),
                _detailRow('访问地址', e.eUrl),
                _detailRow('版本号', e.eVersion),
                _detailRow('更新时间', e.eUpdatetime != null ? _dateFmt.format(e.eUpdatetime!) : null),
                _detailRow('SEE平台', e.eSeeurl),
                _detailRow('Web服务地址', e.eWebserveraddr),
                _detailRow('Web日志路径', e.eWeblogpath),
                _detailRow('备注', e.eMemo),
                _detailRow('数据库类型', e.eDbtype),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  TableRow _detailRow(String label, String? value) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.all(6),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      ),
      Padding(
        padding: const EdgeInsets.all(6),
        child: SelectableText(value ?? '-'),
      ),
    ]);
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
