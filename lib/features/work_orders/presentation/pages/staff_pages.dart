import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../profile/presentation/profile_cubit.dart';
import '../../../../core/session/app_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/eyebrow.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/key_value_row.dart';
import '../../../../core/widgets/labelled_field.dart';
import '../../../../core/widgets/link_text_button.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../../core/widgets/page_frames.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../attendance/presentation/attendance_page.dart';
import '../../data/sample_work_orders.dart';
import '../../domain/work_order.dart';
import '../bloc/work_orders_bloc.dart';
import '../widgets/work_order_card.dart';
import '../widgets/work_order_scope.dart';

class StaffHomePage extends StatelessWidget {
  const StaffHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.assignedTo(sampleStaff),
    );
    final clockedIn = context.select<AttendanceCubit, bool>(
      (cubit) => cubit.state.contains(AppRole.staff),
    );
    final me = context.profileOf(AppRole.staff);
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final todo = orders
        .where((o) => o.isEditableByStaff || o.status == WorkOrderStatus.open)
        .toList();
    final sla = todo.where((o) => o.type == WorkOrderType.sla).length;
    final done = orders.where((o) => !o.status.isActive).length;
    return TabPage(
      title: 'Home',
      role: AppRole.staff,
      children: [
        Eyebrow(longDateLabel(now)),
        const SizedBox(height: 8),
        Text(
          '${greetingFor(now)}, ${me.firstName} 👋',
          style: text.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Let’s keep ${me.facility.split(',').first} running smoothly.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                clockedIn ? 'You’re clocked in' : 'Ready for your shift?',
                style: text.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(me.facility, style: text.bodyMedium),
              const SizedBox(height: 12),
              if (clockedIn)
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.staffClock),
                  child: const Text('View attendance'),
                )
              else
                FilledButton(
                  onPressed: () => context.go(AppRoutes.staffClock),
                  child: const Text('Clock in with GPS'),
                ),
            ],
          ),
        ),
        StatRow(
          first: StatTile(
            icon: Icons.assignment_outlined,
            label: 'To do',
            value: '${todo.length}',
            caption: '$sla SLA · ${todo.length - sla} client',
          ),
          second: StatTile(
            icon: Icons.task_alt,
            label: 'Completed',
            value: '$done',
            caption: 'Confirmed work',
            iconColor: AppColors.teal,
            iconBackground: AppColors.successSoft,
          ),
        ),
        SectionHeader(
          'Up next',
          trailing: LinkTextButton(
            'View all',
            onPressed: () => context.go(AppRoutes.staffTasks),
          ),
        ),
        for (final order in todo.take(3))
          WorkOrderCard(
            order: order,
            onTap: () => context.push(AppRoutes.staffTask(order.id)),
          ),
      ],
    );
  }
}

class AssignedTasksPage extends StatelessWidget {
  const AssignedTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.assignedTo(sampleStaff),
    );
    final endOfToday = DateUtils.dateOnly(DateTime.now())
        .add(const Duration(days: 1));
    bool toDo(WorkOrder o) =>
        o.status == WorkOrderStatus.open || o.isEditableByStaff;
    final today = orders
        .where((o) => toDo(o) && o.due.isBefore(endOfToday))
        .toList();
    final upcoming = orders
        .where((o) => toDo(o) && !o.due.isBefore(endOfToday))
        .toList();
    final submitted = orders.where((o) => !toDo(o)).toList();

    Widget list(List<WorkOrder> items, String empty) => items.isEmpty
        ? EmptyListMessage(empty)
        : ListView(
            padding: pagePadding,
            children: [
              for (final order in items)
                WorkOrderCard(
                  order: order,
                  onTap: () => context.push(
                    toDo(order)
                        ? AppRoutes.staffTask(order.id)
                        : AppRoutes.staffSubmission(order.id),
                  ),
                ),
            ],
          );

    return DefaultTabController(
      length: 3,
      child: TabPageFrame(
        title: 'Assigned tasks',
        role: AppRole.staff,
        child: Column(
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Today (${today.length})'),
                  Tab(text: 'Upcoming (${upcoming.length})'),
                  Tab(text: 'Submitted (${submitted.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  list(today, 'Nothing left for today.'),
                  list(upcoming, 'No upcoming tasks.'),
                  list(submitted, 'You haven’t submitted any work yet.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskEvidencePage extends StatefulWidget {
  const TaskEvidencePage({required this.id, super.key});

  final String id;

  @override
  State<TaskEvidencePage> createState() => _TaskEvidencePageState();
}

class _TaskEvidencePageState extends State<TaskEvidencePage> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  var _media = const <String>[];
  var _showMediaError = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final formValid = _form.currentState!.validate();
    setState(() => _showMediaError = _media.isEmpty);
    if (!formValid || _media.isEmpty) return;
    final note = _note.text.trim();
    final media = _media;
    context.read<WorkOrdersBloc>().add(
      WorkOrderChanged(
        widget.id,
        (order, now) => order.submit(note: note, media: media, at: now),
      ),
    );
    context.pushReplacement(
      AppRoutes.staffSubmission(widget.id, justSubmitted: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        return DetailPage(
          title: 'Task & evidence',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: WorkOrderBadges(order, showPriority: true),
            ),
            const SizedBox(height: 10),
            Text(order.title, style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${order.id} · ${order.type.label} · Due '
              '${dateTimeLabel(order.due, DateTime.now())}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.type == WorkOrderType.sla
                        ? 'Task details'
                        : 'Reported issue',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(order.description, style: text.bodyMedium),
                  if (order.reportMedia.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    MediaGrid(order.reportMedia),
                  ],
                  const SizedBox(height: 4),
                  KeyValueRow('Location', order.location),
                  KeyValueRow(
                    'Zone',
                    order.zone,
                    divider: order.type == WorkOrderType.client,
                  ),
                  if (order.type == WorkOrderType.client)
                    KeyValueRow(
                      'Reported by',
                      order.submittedBy,
                      divider: false,
                    ),
                ],
              ),
            ),
            if (order.assignmentNote != null && order.status.isActive)
              InfoBanner(
                'Note from your supervisor: ${order.assignmentNote}',
                icon: Icons.sticky_note_2_outlined,
                tone: BannerTone.neutral,
              ),
            if (order.status.isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.chat(AppRole.staff, order.id),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Message'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.staffPartsNew(workOrderId: order.id),
                        ),
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('Request parts'),
                      ),
                    ),
                  ],
                ),
              ),
            if (order.status == WorkOrderStatus.returned) _ReturnNotice(order),
            ..._actions(context, order),
          ],
        );
      },
    );
  }

  List<Widget> _actions(BuildContext context, WorkOrder order) {
    if (order.status == WorkOrderStatus.open) return [_StartWork(order)];
    if (!order.isEditableByStaff) {
      return [
        const InfoBanner(
          'Submitted. Editing is locked pending supervisor review.',
          icon: Icons.lock_outline,
        ),
        FilledButton(
          onPressed: () => context.push(AppRoutes.staffSubmission(order.id)),
          child: const Text('View submission'),
        ),
      ];
    }
    return [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabelledTextField(
              label: 'Work update',
              hint: 'What did you do, and what is the result?',
              controller: _note,
              maxLines: 4,
              validator: (value) =>
                  requiredText(value, 'Describe the work you carried out'),
            ),
            MediaPickerField(
              label: 'Add proof of completed work',
              onChanged: (media) => setState(() {
                _media = media;
                if (media.isNotEmpty) _showMediaError = false;
              }),
            ),
            if (_showMediaError)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Add at least one photo as proof.',
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('Mark as done & submit'),
            ),
          ],
        ),
      ),
    ];
  }
}

class _StartWork extends StatelessWidget {
  const _StartWork(this.order);

  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    final clockedIn = context.select<AttendanceCubit, bool>(
      (cubit) => cubit.state.contains(AppRole.staff),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!clockedIn) ...[
          const InfoBanner(
            'Clock in with GPS before you start work on this task.',
            icon: Icons.location_on_outlined,
            tone: BannerTone.warning,
          ),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.staffClock),
            child: const Text('Go to clock in'),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: clockedIn
              ? () => context.read<WorkOrdersBloc>().add(
                  WorkOrderChanged(
                    order.id,
                    (current, now) => current.start(now),
                  ),
                )
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start work'),
        ),
      ],
    );
  }
}

class _ReturnNotice extends StatelessWidget {
  const _ReturnNotice(this.order);

  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppBadge('Returned by supervisor', tone: BadgeTone.danger),
          const SizedBox(height: 10),
          Text(
            order.returnReason ?? 'Correction needed',
            style: text.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(order.returnFeedback ?? '', style: text.bodyMedium),
          if (order.returnMedia.isNotEmpty) ...[
            const SizedBox(height: 12),
            MediaGrid(order.returnMedia),
          ],
        ],
      ),
    );
  }
}

class SubmissionPage extends StatelessWidget {
  const SubmissionPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        final returned = order.status == WorkOrderStatus.returned;
        final completed = order.status == WorkOrderStatus.completed;
        final submittedAt = order.submittedAt;
        final images = order.workMedia.length;
        return DetailPage(
          title: completed ? 'Completed work' : 'Submission',
          children: [
            const SizedBox(height: 12),
            Icon(
              returned ? Icons.undo : Icons.check_circle_outline,
              size: 52,
              color: returned ? AppColors.danger : AppColors.primary,
            ),
            const SizedBox(height: 14),
            Text(
              returned
                  ? 'Returned for correction'
                  : completed
                  ? 'Work confirmed'
                  : 'Work submitted',
              textAlign: TextAlign.center,
              style: text.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              returned
                  ? 'Your supervisor has requested a correction.'
                  : completed
                  ? 'Your supervisor confirmed and closed this work.'
                  : 'Your supervisor will review and confirm the work.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.title, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${order.id} · ${order.assignee ?? 'Unassigned'}',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  WorkOrderBadges(order),
                  const SizedBox(height: 4),
                  if (submittedAt != null)
                    KeyValueRow(
                      'Submission time',
                      dateTimeLabel(submittedAt, DateTime.now()),
                    ),
                  KeyValueRow(
                    'Evidence',
                    '$images ${images == 1 ? 'image' : 'images'}',
                    divider: false,
                  ),
                ],
              ),
            ),
            if (returned) ...[
              InfoBanner(
                'Supervisor: ${order.returnFeedback ?? 'See the task for details.'}',
                icon: Icons.undo,
                tone: BannerTone.danger,
              ),
              FilledButton(
                onPressed: () =>
                    context.pushReplacement(AppRoutes.staffTask(order.id)),
                child: const Text('Continue correction'),
              ),
            ] else ...[
              if (!completed)
                const InfoBanner(
                  'Task editing is locked until a supervisor returns it.',
                  icon: Icons.lock_outline,
                ),
              if ((order.workNote ?? '').isNotEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your work update', style: text.titleSmall),
                      const SizedBox(height: 6),
                      Text(order.workNote!, style: text.bodyMedium),
                      const SizedBox(height: 12),
                      MediaGrid(order.workMedia),
                    ],
                  ),
                ),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.staffTasks),
                child: const Text('Back to my tasks'),
              ),
            ],
          ],
        );
      },
    );
  }
}
