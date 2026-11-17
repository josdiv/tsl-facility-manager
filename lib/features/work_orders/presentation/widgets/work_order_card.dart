import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/work_order.dart';

BadgeTone toneFor(WorkOrderStatus status) => switch (status) {
  WorkOrderStatus.open => BadgeTone.warning,
  WorkOrderStatus.inProgress => BadgeTone.info,
  WorkOrderStatus.pendingReview => BadgeTone.warning,
  WorkOrderStatus.returned => BadgeTone.danger,
  WorkOrderStatus.completed => BadgeTone.success,
};

/// Status, plus the priority and overdue flags when they apply.
class WorkOrderBadges extends StatelessWidget {
  const WorkOrderBadges(
    this.order, {
    this.clientView = false,
    this.showPriority = false,
    super.key,
  });

  final WorkOrder order;
  final bool clientView;
  final bool showPriority;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        AppBadge(
          clientView ? order.status.clientLabel : order.status.label,
          tone: clientView && order.status == WorkOrderStatus.returned
              ? BadgeTone.info
              : toneFor(order.status),
        ),
        if (!clientView && order.isOverdueAt(DateTime.now()))
          const AppBadge('Overdue', tone: BadgeTone.danger),
        if (showPriority && order.isHighPriority)
          const AppBadge('High', tone: BadgeTone.danger),
      ],
    );
  }
}

class WorkOrderCard extends StatelessWidget {
  const WorkOrderCard({
    required this.order,
    required this.onTap,
    this.clientView = false,
    this.actionLabel = 'View task',
    super.key,
  });

  final WorkOrder order;
  final VoidCallback onTap;
  final bool clientView;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${order.id} · ${order.type.label}', style: text.bodySmall),
          const SizedBox(height: 8),
          WorkOrderBadges(
            order,
            clientView: clientView,
            showPriority: !clientView,
          ),
          const SizedBox(height: 10),
          Text(order.title, style: text.titleMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${order.location.split(',').first} · ${order.zone}',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Due ${dateTimeLabel(order.due, DateTime.now())}',
                  style: text.bodySmall,
                ),
              ),
              Text(
                '$actionLabel →',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
