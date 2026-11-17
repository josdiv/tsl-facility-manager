import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_frames.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';
import '../domain/notifications.dart';

IconData _iconFor(NoticeKind kind) => switch (kind) {
  NoticeKind.assigned => Icons.engineering_outlined,
  NoticeKind.returned => Icons.undo,
  NoticeKind.slaDue => Icons.schedule,
  NoticeKind.submitted => Icons.fact_check_outlined,
  NoticeKind.completed => Icons.task_alt,
  NoticeKind.message => Icons.chat_bubble_outline,
  NoticeKind.requisition => Icons.inventory_2_outlined,
  NoticeKind.system => Icons.notifications_none,
};

/// Where tapping a notification about [workOrderId] goes for [role].
String _routeFor(AppRole role, String workOrderId) => switch (role) {
  AppRole.client => AppRoutes.clientRequest(workOrderId),
  AppRole.staff => AppRoutes.staffTask(workOrderId),
  AppRole.supervisor => AppRoutes.supervisorOrder(workOrderId),
};

/// "Just now", "12 min ago", or the date.
String ageLabel(DateTime at, DateTime now) {
  final minutes = now.difference(at).inMinutes;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  return dateTimeLabel(at, now);
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.role, super.key});

  final AppRole role;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? _uid;
  Stream<List<Notice>> _notices = const Stream.empty();

  @override
  Widget build(BuildContext context) {
    final me = context.profileOf(widget.role);
    if (me.uid != _uid) {
      _uid = me.uid;
      _notices = context.read<NotificationRepository>().watch(me);
    }
    final content = StreamBuilder<List<Notice>>(
      stream: _notices,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Notice>[];
        final unread = all.where((n) => !n.read).toList();

        Widget list(List<Notice> items, String empty) => items.isEmpty
            ? EmptyListMessage(empty)
            : ListView(
                padding: pagePadding,
                children: [for (final item in items) _tile(context, me, item)],
              );

        return Column(
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
      },
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

  Widget _tile(BuildContext context, UserProfile me, Notice item) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () {
        if (!item.read) {
          context.read<NotificationRepository>().markRead(me, item);
        }
        final workOrderId = item.workOrderId;
        if (workOrderId != null) {
          context.push(_routeFor(widget.role, workOrderId));
        }
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
            child: Icon(
              _iconFor(item.kind),
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: text.titleSmall?.copyWith(
                    color: item.read ? AppColors.muted : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.body, style: text.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  ageLabel(item.createdAt, DateTime.now()),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          if (!item.read)
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
