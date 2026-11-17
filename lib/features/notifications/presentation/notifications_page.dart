import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_frames.dart';
import '../../work_orders/data/sample_work_orders.dart';
import '../../work_orders/domain/work_order.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';

class AppNotification {
  const AppNotification(
    this.icon,
    this.title,
    this.detail,
    this.age,
    this.route,
  );

  final IconData icon;
  final String title;
  final String detail;
  final String age;
  final String route;
}

/// Sample alerts per role. Returned work comes from live sample data, so the
/// staff alert appears as soon as a supervisor returns a task.
List<AppNotification> notificationsFor(AppRole role, WorkOrdersState state) {
  return switch (role) {
    AppRole.client => [
      AppNotification(
        Icons.engineering_outlined,
        'Technician assigned',
        'Emeka Okafor is working on WO-1048',
        '35 min ago',
        AppRoutes.clientRequest('WO-1048'),
      ),
      AppNotification(
        Icons.task_alt,
        'Request resolved',
        'WO-1040 Office door lock repair is complete',
        '3 days ago',
        AppRoutes.clientRequest('WO-1040'),
      ),
    ],
    AppRole.staff => [
      for (final order in state.assignedTo(sampleStaff))
        if (order.status == WorkOrderStatus.returned)
          AppNotification(
            Icons.undo,
            'Task returned for correction',
            '${order.id} · ${order.returnReason ?? order.title}',
            'Just now',
            AppRoutes.staffTask(order.id),
          ),
      AppNotification(
        Icons.schedule,
        'SLA task due',
        'WO-1045 Fire extinguisher inspection · Marina Towers',
        '12 min ago',
        AppRoutes.staffTask('WO-1045'),
      ),
      AppNotification(
        Icons.swap_horiz,
        'New assignment',
        'WO-1047 Monthly generator service was assigned to you',
        '35 min ago',
        AppRoutes.staffTask('WO-1047'),
      ),
    ],
    AppRole.supervisor => [
      AppNotification(
        Icons.schedule,
        'SLA task overdue',
        'WO-1045 Fire extinguisher inspection · Marina Towers',
        'Just now',
        AppRoutes.supervisorOrder('WO-1045'),
      ),
      for (final order in state.awaitingReview)
        AppNotification(
          Icons.fact_check_outlined,
          'Work ready for review',
          '${order.assignee ?? 'Staff'} submitted ${order.id} with '
              '${order.workMedia.length} '
              '${order.workMedia.length == 1 ? 'attachment' : 'attachments'}',
          '12 min ago',
          AppRoutes.supervisorOrder(order.id),
        ),
      AppNotification(
        Icons.swap_horiz,
        'New assignment',
        'WO-1047 assigned to your team',
        '35 min ago',
        AppRoutes.supervisorOrder('WO-1047'),
      ),
    ],
  };
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.role, super.key});

  final AppRole role;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _read = <String>{};

  @override
  Widget build(BuildContext context) {
    final all = notificationsFor(
      widget.role,
      context.watch<WorkOrdersBloc>().state,
    );
    final unread = all
        .where((n) => !_read.contains(n.title + n.detail))
        .toList();

    Widget list(List<AppNotification> items, String empty) => items.isEmpty
        ? EmptyListMessage(empty)
        : ListView(
            padding: pagePadding,
            children: [for (final item in items) _tile(context, item)],
          );

    final content = Column(
      children: [
        ColoredBox(
          color: AppColors.surface,
          child: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'All notifications'),
              Tab(text: 'Unread (${unread.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              list(all, 'No notifications yet.'),
              list(unread, 'You’re all caught up.'),
            ],
          ),
        ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: widget.role == AppRole.supervisor
          ? TabPageFrame(title: 'Alerts', role: widget.role, child: content)
          : Scaffold(
              appBar: AppBar(title: const Text('Notifications')),
              body: SafeArea(top: false, child: content),
            ),
    );
  }

  Widget _tile(BuildContext context, AppNotification item) {
    final text = Theme.of(context).textTheme;
    final isRead = _read.contains(item.title + item.detail);
    return AppCard(
      onTap: () {
        setState(() => _read.add(item.title + item.detail));
        context.push(item.route);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: text.titleSmall?.copyWith(
                    color: isRead ? AppColors.muted : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.detail, style: text.bodyMedium),
                const SizedBox(height: 4),
                Text(item.age, style: text.bodySmall),
              ],
            ),
          ),
          if (!isRead)
            Semantics(
              label: 'Unread',
              child: Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 8, top: 4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
