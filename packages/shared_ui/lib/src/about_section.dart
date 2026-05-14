import 'package:flutter/material.dart';

class LabelValueRow {
  final String label;
  final String value;
  const LabelValueRow(this.label, this.value);
}

class Section extends StatelessWidget {
  final String title;
  final List<LabelValueRow> rows;

  const Section({super.key, required this.title, required this.rows});

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
            for (final row in rows)
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
        ),
      ),
    );
  }
}
