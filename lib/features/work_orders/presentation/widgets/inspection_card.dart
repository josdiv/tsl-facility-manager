import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../domain/work_order.dart';

/// What the supervisor recorded when confirming the work: the checklist, the
/// note and the inspection photos. Shows nothing until the work is completed.
class InspectionCard extends StatelessWidget {
  const InspectionCard(this.order, {super.key});

  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    if (order.status != WorkOrderStatus.completed) {
      return const SizedBox.shrink();
    }
    final note = order.inspectionNote?.trim();
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Supervisor inspection', style: text.titleMedium),
              ),
            ],
          ),
          for (final check in order.inspectionChecks)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 18, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text(check, style: text.bodyMedium)),
                ],
              ),
            ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(note, style: text.bodyMedium),
          ],
          if (order.inspectionChecks.isEmpty &&
              (note == null || note.isEmpty) &&
              order.inspectionMedia.isEmpty) ...[
            const SizedBox(height: 8),
            Text('Confirmed without notes.', style: text.bodySmall),
          ],
          if (order.inspectionMedia.isNotEmpty) ...[
            const SizedBox(height: 12),
            MediaGrid(order.inspectionMedia),
          ],
        ],
      ),
    );
  }
}
