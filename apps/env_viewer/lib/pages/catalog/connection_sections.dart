import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/backend_client.dart';
import '../../catalog/catalog_acl.dart';
import '../../inventory/inventory_view.dart';

/// `SSH 信息` — the non-secret SSH coordinates for the Server a Component runs on,
/// with an on-demand password reveal/copy brokered just-in-time (ADR-0008). The
/// address renders from already-loaded inventory; the password is fetched from
/// `GET /api/servers/{id}/credentials` only when the user asks, and never cached
/// beyond this widget's lifetime. Masked by default so a glance at — or screenshot
/// of — the catalog never sprays plaintext credentials.
class SshInfoSection extends StatefulWidget {
  final int serverId;
  final ServerView? server;

  const SshInfoSection({super.key, required this.serverId, this.server});

  @override
  State<SshInfoSection> createState() => _SshInfoSectionState();
}

class _SshInfoSectionState extends State<SshInfoSection> {
  bool _busy = false;
  bool _revealed = false;
  String? _secret;
  int _requestVersion = 0;

  /// Fetch for one explicit user action. The version check makes a response from
  /// a Server that is no longer rendered inert, including when navigation happens
  /// while the broker request is still in flight.
  Future<({bool completed, String? secret})> _fetchSecret() async {
    final requestVersion = ++_requestVersion;
    final serverId = widget.serverId;
    final client = context.read<BackendClient>();
    setState(() => _busy = true);
    try {
      final cred = await client.getServerCredentials(serverId);
      if (!_isCurrent(requestVersion, serverId)) {
        return (completed: false, secret: null);
      }
      return (completed: true, secret: cred.secret);
    } on BackendException catch (e) {
      if (_isCurrent(requestVersion, serverId)) _toast(e.message);
      return (completed: false, secret: null);
    } finally {
      if (_isCurrent(requestVersion, serverId)) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isCurrent(int requestVersion, int serverId) =>
      mounted &&
      requestVersion == _requestVersion &&
      serverId == widget.serverId;

  Future<void> _toggleReveal() async {
    if (_revealed) {
      setState(() {
        _revealed = false;
        _secret = null;
      });
      return;
    }
    final result = await _fetchSecret();
    if (!mounted || !result.completed) return;
    if (result.secret == null) {
      _toast('未配置密码');
      return;
    }
    setState(() {
      _secret = result.secret;
      _revealed = true;
    });
  }

  Future<void> _copy() async {
    final result = await _fetchSecret();
    if (!mounted || !result.completed) return;
    final secret = result.secret;
    if (secret == null) {
      if (_revealed || _secret != null) {
        setState(() {
          _revealed = false;
          _secret = null;
        });
      }
      _toast('未配置密码');
      return;
    }
    if (_revealed) setState(() => _secret = secret);
    await Clipboard.setData(ClipboardData(text: secret));
    if (mounted) _toast('已复制密码');
  }

  @override
  void didUpdateWidget(covariant SshInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) {
      _requestVersion++;
      _busy = false;
      _revealed = false;
      _secret = null;
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _secret = null;
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = widget.server?.sshAddress ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('SSH 信息'),
        const SizedBox(height: 6),
        if (address.isNotEmpty)
          SelectableText(address, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              '密码',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _revealed && _secret != null
                  ? SelectableText(_secret!, style: theme.textTheme.bodyMedium)
                  : Text('••••••', style: theme.textTheme.bodyMedium),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                icon: Icon(
                  _revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                tooltip: _revealed ? '隐藏密码' : '显示密码',
                visualDensity: VisualDensity.compact,
                onPressed: _toggleReveal,
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: '复制密码',
                visualDensity: VisualDensity.compact,
                onPressed: _copy,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// `数据库信息` — one row per Database a Component uses, each with a 复制 action that
/// assembles the full `username/password@host:port/serviceName` sqlplus connect
/// string at click-time (ADR-0008). One row per database fixes the cramped, mid-label
/// wrapping of the old inline `使用数据库` field. The password only ever reaches the
/// clipboard (an explicit act), never the screen.
class DatabaseInfoSection extends StatelessWidget {
  final List<int> databaseIds;
  final Map<int, DatabaseView> databaseRefs;

  const DatabaseInfoSection({
    super.key,
    required this.databaseIds,
    required this.databaseRefs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('数据库信息'),
        const SizedBox(height: 6),
        for (final id in databaseIds)
          _DatabaseRow(
            key: ValueKey(id),
            databaseId: id,
            ref: databaseRefs[id],
          ),
      ],
    );
  }
}

class _DatabaseRow extends StatefulWidget {
  final int databaseId;
  final DatabaseView? ref;

  const _DatabaseRow({super.key, required this.databaseId, this.ref});

  @override
  State<_DatabaseRow> createState() => _DatabaseRowState();
}

class _DatabaseRowState extends State<_DatabaseRow> {
  bool _busy = false;
  int _requestVersion = 0;

  Future<void> _copy() async {
    final requestVersion = ++_requestVersion;
    final databaseId = widget.databaseId;
    final client = context.read<BackendClient>();
    setState(() => _busy = true);
    try {
      final cred = await client.getDatabaseCredentials(databaseId);
      if (!_isCurrent(requestVersion, databaseId)) return;
      final connect = CatalogAcl.sqlplusConnectString(
        username: cred.username,
        password: cred.secret,
        host: cred.host,
        port: cred.port,
        serviceName: cred.serviceName,
      );
      if (connect.isEmpty) {
        _toast('该数据库没有连接信息');
        return;
      }
      if (!_isCurrent(requestVersion, databaseId)) return;
      await Clipboard.setData(ClipboardData(text: connect));
      if (_isCurrent(requestVersion, databaseId)) {
        _toast(cred.secret == null ? '已复制连接串（无密码）' : '已复制连接串');
      }
    } on BackendException catch (e) {
      if (_isCurrent(requestVersion, databaseId)) _toast(e.message);
    } finally {
      if (_isCurrent(requestVersion, databaseId)) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isCurrent(int requestVersion, int databaseId) =>
      mounted &&
      requestVersion == _requestVersion &&
      databaseId == widget.databaseId;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didUpdateWidget(covariant _DatabaseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.databaseId != widget.databaseId) {
      _requestVersion++;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.ref?.displayLabel ?? '#${widget.databaseId}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(label, style: theme.textTheme.bodyMedium),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: '复制 sqlplus 连接串',
              visualDensity: VisualDensity.compact,
              onPressed: _copy,
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.outline,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
