import 'package:flutter/material.dart';

import 'theme.dart';

/// Meaning of a [StatusChip], mapped to the strict token status language:
/// green = collected OK, red = failed, neutral = not collected, na = the
/// resource opted out (e.g. an UNSUPPORTED probe) and does not count.
enum StatusChipKind { ok, err, none, na }

/// Compact status chip. Color is used only for meaning: ok/err carry the
/// green/red status colors, none/na render neutrally.
class StatusChip extends StatelessWidget {
  final StatusChipKind kind;
  final String label;

  const StatusChip({super.key, required this.kind, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (Color bg, Color fg) = switch (kind) {
      StatusChipKind.ok => (tokens.okBg, tokens.ok),
      StatusChipKind.err => (tokens.errBg, tokens.err),
      StatusChipKind.none => (tokens.neutralChipBg, tokens.textSecondary),
      StatusChipKind.na => (tokens.neutralChipBg, tokens.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// `#id` badge in mono, used wherever a numeric identity anchors a row/header.
class IdBadge extends StatelessWidget {
  final int id;

  const IdBadge({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.neutralChipBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Text(
        '#$id',
        style: tokens.mono(
          fontSize: 12,
          color: tokens.textSecondary,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Inline error surface with a 重试 affordance.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: tokens.errBg,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.err, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: tokens.err)),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// Centered placeholder for an empty list (no data, or no search match).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: tokens.textSecondary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: tokens.textSecondary)),
        ],
      ),
    );
  }
}

/// One `label: value` line; the value is machine data and renders in mono.
/// Kept constructor-compatible with the old about-section data class.
class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;

  const LabelValueRow(
    this.label,
    this.value, {
    super.key,
    this.labelWidth = 100,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: TextStyle(color: tokens.textSecondary)),
          ),
          Expanded(child: SelectableText(value, style: tokens.mono())),
        ],
      ),
    );
  }
}

/// Standard page header: title + `显示 N / M 条` + search + primary action +
/// refresh, reflowing to two lines below 900px.
class PageHeader extends StatelessWidget {
  final String title;
  final int visibleCount;
  final int totalCount;
  final Widget? search;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    required this.visibleCount,
    required this.totalCount,
    this.search,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final summary = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        Text(
          '显示 $visibleCount / $totalCount 条',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
    final actionRow = Row(mainAxisSize: MainAxisSize.min, children: actions);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    actionRow,
                  ],
                ),
                if (search != null) ...[const SizedBox(height: 8), search!],
              ],
            );
          }
          return Row(
            children: [
              summary,
              const Spacer(),
              if (search != null) ...[
                SizedBox(width: 340, child: search!),
                const SizedBox(width: 8),
              ],
              actionRow,
            ],
          );
        },
      ),
    );
  }
}
