import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/session/app_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/eyebrow.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/key_value_row.dart';
import '../../../../core/widgets/labelled_field.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../../core/widgets/page_frames.dart';
import '../../../../core/widgets/progress_timeline.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../attendance/presentation/attendance_page.dart';
import '../../domain/work_order.dart';
import '../bloc/work_orders_bloc.dart';
import '../widgets/work_order_card.dart';
import '../widgets/work_order_scope.dart';

/// Workers assigned to the sample facility.
const facilityWorkers = [
  ('Emeka Okafor', 'EO', 'HVAC technician', 'On site'),
  ('Tunde Bakare', 'TB', 'Electrician', 'On site'),
  ('David Adeyemi', 'DA', 'General maintenance', 'On site'),
  ('Grace Eze', 'GE', 'Safety officer', 'Off shift'),
];

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class SupervisorHomePage extends StatelessWidget {
  const SupervisorHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.select<WorkOrdersBloc, List>(
      (bloc) => bloc.state.awaitingReview,
    );
    final clockedIn = context.select<AttendanceCubit, bool>(
      (cubit) => cubit.state.contains(AppRole.supervisor),
    );
    final text = Theme.of(context).textTheme;
    return TabPage(
      title: 'Home',
      role: AppRole.supervisor,
      children: [
        const Eyebrow('Marina Towers · Supervisor'),
        const SizedBox(height: 8),
        Text('Hello, Sarah 👋', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Your team is making good progress today.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('On-site attendance', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      clockedIn
                          ? 'Clocked in · GPS verified'
                          : 'Clock in before your shift',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.supervisorClock),
                child: const Text('GPS'),
              ),
            ],
          ),
        ),
        StatRow(
          first: StatTile(
            icon: Icons.fact_check_outlined,
            label: 'Awaiting review',
            value: '${queue.length}',
            caption: 'Staff submissions',
          ),
          second: const StatTile(
            icon: Icons.groups_outlined,
            label: 'Team on-site',
            value: '3 / 4',
            caption: 'GPS verified',
            iconColor: AppColors.teal,
            iconBackground: AppColors.successSoft,
          ),
        ),
        SectionHeader(
          'Ready for inspection',
          trailing: AppBadge(
            '${queue.length} pending',
            tone: BadgeTone.warning,
          ),
        ),
        if (queue.isEmpty)
          const EmptyListMessage('Nothing is waiting for review.'),
        for (final order in queue)
          WorkOrderCard(
            order: order,
            actionLabel: 'Inspect',
            onTap: () => context.push(AppRoutes.supervisorOrder(order.id)),
          ),
        AppCard(
          onTap: () => context.go(AppRoutes.supervisorAlerts),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Upcoming SLA reminder', style: text.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Fire extinguisher inspection · All floors',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gap in the design: the Review tab jumped straight to one task, so
/// supervisors had no list of submissions or of team work to reassign.
class ReviewListPage extends StatelessWidget {
  const ReviewListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrdersBloc>().state;
    final queue = state.awaitingReview;
    final team = state.teamActive;

    Widget list(List items, String empty, String action) => items.isEmpty
        ? EmptyListMessage(empty)
        : ListView(
            padding: pagePadding,
            children: [
              for (final order in items)
                WorkOrderCard(
                  order: order,
                  actionLabel: action,
                  onTap: () =>
                      context.push(AppRoutes.supervisorOrder(order.id)),
                ),
            ],
          );

    return DefaultTabController(
      length: 2,
      child: TabPageFrame(
        title: 'Review',
        role: AppRole.supervisor,
        child: Column(
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'To review (${queue.length})'),
                  Tab(text: 'Team work (${team.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  list(queue, 'Nothing is waiting for review.', 'Inspect'),
                  list(team, 'No active team work.', 'View'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewInspectPage extends StatefulWidget {
  const ReviewInspectPage({required this.id, super.key});

  final String id;

  @override
  State<ReviewInspectPage> createState() => _ReviewInspectPageState();
}

class _ReviewInspectPageState extends State<ReviewInspectPage> {
  static const _checks = [
    'Unit operating correctly',
    'Area clean and safe',
    'Evidence meets requirements',
  ];
  final _ticked = <String>{};
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _confirm() {
    final note = _notes.text.trim();
    context.read<WorkOrdersBloc>().add(
      WorkOrderChanged(
        widget.id,
        (order, now) =>
            order.confirm(at: now, inspectionNote: note.isEmpty ? null : note),
      ),
    );
    _toast(context, '${widget.id} confirmed and closed');
    context.go(AppRoutes.supervisorReview);
  }

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        final submittedAt = order.submittedAt;
        final assignee = order.assignee ?? 'Unassigned';
        final canConfirm = _ticked.length == _checks.length;
        return DetailPage(
          title: order.isAwaitingReview ? 'Review & inspect' : 'Work order',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: WorkOrderBadges(order, showPriority: true),
            ),
            const SizedBox(height: 10),
            Text(
              order.isAwaitingReview ? 'Inspect completed work' : order.title,
              style: text.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              [
                order.id,
                order.isAwaitingReview ? order.title : order.type.label,
                'Due ${dateTimeLabel(order.due, DateTime.now())}',
              ].join(' · '),
              style: text.bodyMedium,
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InitialsAvatar(
                        assignee
                            .split(' ')
                            .take(2)
                            .map((part) => part[0])
                            .join(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(assignee, style: text.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              submittedAt == null
                                  ? 'Not submitted yet'
                                  : 'Submitted '
                                        '${dateTimeLabel(submittedAt, DateTime.now())}',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    order.workNote ?? order.description,
                    style: text.bodyMedium,
                  ),
                  if (order.workMedia.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    MediaGrid(order.workMedia),
                  ],
                ],
              ),
            ),
            if (order.isAwaitingReview) ...[
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inspection checklist', style: text.titleMedium),
                    const SizedBox(height: 4),
                    for (final check in _checks)
                      CheckboxListTile(
                        value: _ticked.contains(check),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(check, style: text.bodyMedium),
                        onChanged: (value) => setState(() {
                          value == true
                              ? _ticked.add(check)
                              : _ticked.remove(check);
                        }),
                      ),
                  ],
                ),
              ),
              LabelledTextField(
                label: 'Supervisor inspection notes',
                hint: 'Anything to record before closure?',
                controller: _notes,
                maxLines: 3,
              ),
              const MediaPickerField(label: 'Attach inspection photos'),
              // Always shown, so ticking the last item doesn't make the page
              // jump.
              InfoBanner(
                canConfirm
                    ? 'All checks done. You can confirm and close.'
                    : 'Tick every checklist item to confirm and close.',
                icon: canConfirm ? Icons.check_circle_outline : Icons.checklist,
                tone: canConfirm ? BannerTone.success : BannerTone.neutral,
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                onPressed: canConfirm ? _confirm : null,
                icon: const Icon(Icons.check),
                label: const Text('Confirm & close'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: () =>
                    context.push(AppRoutes.supervisorReturn(order.id)),
                icon: const Icon(Icons.undo),
                label: const Text('Return'),
              ),
              const SizedBox(height: 8),
            ],
            if (order.status.isActive) ...[
              OutlinedButton(
                onPressed: () =>
                    context.push(AppRoutes.supervisorReassign(order.id)),
                child: const Text('Reassign'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(AppRoutes.chat(AppRole.supervisor, order.id)),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Message'),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History', style: text.titleMedium),
                  const SizedBox(height: 14),
                  ProgressTimeline([
                    for (final event in order.history.reversed)
                      TimelineStep(
                        event.title,
                        [
                          dateTimeLabel(event.at, DateTime.now()),
                          ?event.note,
                        ].join(' · '),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class ReturnWithEvidencePage extends StatefulWidget {
  const ReturnWithEvidencePage({required this.id, super.key});

  final String id;

  @override
  State<ReturnWithEvidencePage> createState() => _ReturnWithEvidencePageState();
}

class _ReturnWithEvidencePageState extends State<ReturnWithEvidencePage> {
  static const _reasons = [
    'Incomplete finishing',
    'Work not satisfactory',
    'Safety concern',
    'Wrong resolution',
  ];
  final _form = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  var _reason = _reasons.first;
  var _media = const <String>[];
  String? _returnTo;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _submit(String defaultAssignee) {
    if (!_form.currentState!.validate()) return;
    final assignee = _returnTo ?? defaultAssignee;
    final reason = _reason;
    final feedback = _feedback.text.trim();
    final media = _media;
    context.read<WorkOrdersBloc>().add(
      WorkOrderChanged(
        widget.id,
        (order, now) => order.returnForCorrection(
          reason: reason,
          feedback: feedback,
          media: media,
          assignee: assignee,
          at: now,
        ),
      ),
    );
    _toast(context, 'Returned to $assignee · editing unlocked');
    context.go(AppRoutes.supervisorReview);
  }

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        final current = order.assignee ?? facilityWorkers.first.$1;
        final names = [
          current,
          for (final worker in facilityWorkers)
            if (worker.$1 != current) worker.$1,
        ];
        return DetailPage(
          title: 'Return with evidence',
          children: [
            const InfoBanner(
              'Return to staff for correction',
              icon: Icons.undo,
              tone: BannerTone.danger,
            ),
            Text('Show what needs attention', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Include clear feedback and visual evidence.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabelledDropdown(
                    label: 'Return reason',
                    options: _reasons,
                    onChanged: (value) => _reason = value,
                  ),
                  LabelledTextField(
                    label: 'Supervisor feedback',
                    hint: 'What needs to be corrected?',
                    controller: _feedback,
                    maxLines: 4,
                    validator: (value) =>
                        requiredText(value, 'Tell staff what to correct'),
                  ),
                  MediaPickerField(
                    label: 'Add photographic proof',
                    onChanged: (media) => _media = media,
                  ),
                  LabelledDropdown(
                    label: 'Return to',
                    options: names,
                    onChanged: (value) => _returnTo = value,
                  ),
                  const InfoBanner(
                    'The staff member will receive your comments and photos. '
                    'This changes the work order to Returned and unlocks '
                    'editing.',
                    tone: BannerTone.neutral,
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      backgroundColor: AppColors.dangerSoft,
                    ),
                    onPressed: () => _submit(current),
                    child: const Text('Return work order'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class ReassignTaskPage extends StatefulWidget {
  const ReassignTaskPage({required this.id, super.key});

  final String id;

  @override
  State<ReassignTaskPage> createState() => _ReassignTaskPageState();
}

class _ReassignTaskPageState extends State<ReassignTaskPage> {
  String? _selected;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit(String name) {
    final note = _note.text.trim();
    context.read<WorkOrdersBloc>().add(
      WorkOrderChanged(
        widget.id,
        (order, now) => order.reassign(
          assignee: name,
          at: now,
          note: note.isEmpty ? null : note,
        ),
      ),
    );
    _toast(context, 'Reassigned to $name · notification sent');
    // Back to the work order, which now shows the new technician.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.supervisorReview);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        final others = facilityWorkers
            .where((worker) => worker.$1 != order.assignee)
            .toList();
        final selected = _selected ?? others.first.$1;
        return DetailPage(
          title: 'Reassign task',
          children: [
            Text('Choose an available worker', style: text.titleLarge),
            const SizedBox(height: 6),
            Text('${order.id} · ${order.title}', style: text.bodyMedium),
            const SizedBox(height: 12),
            const InfoBanner(
              'Only workers assigned to Marina Towers are shown.',
              tone: BannerTone.neutral,
            ),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (value) => setState(() => _selected = value),
              child: Column(
                children: [
                  for (final worker in others)
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: RadioListTile<String>(
                        value: worker.$1,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.trailing,
                        // The avatar sits in its own slot so the name and the
                        // role line up under each other.
                        secondary: InitialsAvatar(worker.$2),
                        title: Text(worker.$1, style: text.titleSmall),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${worker.$3} · ${worker.$4}',
                            style: text.bodySmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            LabelledTextField(
              label: 'Assignment note',
              hint: 'Anything the worker should know?',
              controller: _note,
              maxLines: 3,
            ),
            FilledButton(
              onPressed: () => _submit(selected),
              child: const Text('Reassign & notify'),
            ),
          ],
        );
      },
    );
  }
}
