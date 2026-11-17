import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    this.valueColor,
    this.divider = true,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Draws a line under the row. Turn it off for the last row in a group.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: divider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Labels keep their natural width, up to half the row, so short
            // labels like "Expected response" stay on one line.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
