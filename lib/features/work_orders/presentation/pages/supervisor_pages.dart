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
import '../../../profile/presentation/profile_cubit.dart';
import '../../domain/work_order.dart';
import '../../domain/work_order_repository.dart';
import '../bloc/work_orders_bloc.dart';
import '../widgets/work_order_card.dart';
import '../widgets/work_order_scope.dart';
import '../widgets/inspection_card.dart';

/// The supervisor's staff at their facility, kept up to date.
class TeamBuilder extends StatefulWidget {
  const TeamBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, List<TeamMember> team) builder;

  @override
  State<TeamBuilder> createState() => _TeamBuilderState();
}

class _TeamBuilderState extends State<TeamBuilder> {
  String? _locationId;
  Stream<List<TeamMember>> _team = const Stream.empty();

  @override
  Widget build(BuildContext context) {
    final locationId = context.profileOf(AppRole.supervisor).locationId ?? '';
    if (locationId != _locationId) {
      _locationId = locationId;
      _team = context.read<WorkOrderRepository>().watchTeam(locationId);
    }
    return StreamBuilder<List<TeamMember>>(
      stream: _team,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data ?? const []),
    );
  }
}

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
    final me = context.profileOf(AppRole.supervisor);
    final text = Theme.of(context).textTheme;
    return TabPage(
      title: 'Home',
      role: AppRole.supervisor,
      children: [
        Eyebrow('${me.facility.split(',').first} · Supervisor'),
        const SizedBox(height: 8),
        Text('Hello, ${me.firstName} 👋', style: text.headlineMedium),
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
        TeamBuilder(
          builder: (context, team) => StatRow(
            first: StatTile(
              icon: Icons.fact_check_outlined,
              label: 'Awaiting review',
              value: '${queue.length}',
              caption: 'Staff submissions',
            ),
            second: StatTile(
              icon: Icons.groups_outlined,
              label: 'Team on-site',
              value: '${team.where((m) => m.onShift).length} / ${team.length}',
              caption: 'GPS verified',
              iconColor: AppColors.teal,
              iconBackground: AppColors.successSoft,
            ),
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
  final _notes = TextEditingController();
  var _media = const <String>[];
  var _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final note = _notes.text.trim();
    final media = _media;
    setState(() => _saving = true);
    final saved = await context.saveWorkOrder(
      widget.id,
      (order, now) => order.confirm(
        at: now,
        inspectionNote: note.isEmpty ? null : note,
        // The inspection checklist was removed for now (23 Nov 2026).
        checks: const [],
        media: media,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) return;
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
            InspectionCard(order),
            if (order.isAwaitingReview) ...[
              LabelledTextField(
                label: 'Supervisor inspection notes',
                hint: 'Anything to record before closure?',
                controller: _notes,
                maxLines: 3,
              ),
              MediaPickerField(
                label: 'Attach inspection photos',
                max: 4,
                onChanged: (media) => _media = media,
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                onPressed: _saving ? null : _confirm,
                icon: const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Confirm & close'),
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
                child: Text(order.assignee == null ? 'Assign' : 'Reassign'),
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
  TeamMember? _returnTo;
  var _saving = false;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _submit(TeamMember? defaultAssignee) async {
    if (!_form.currentState!.validate()) return;
    final assignee = _returnTo ?? defaultAssignee;
    if (assignee == null) return;
    final reason = _reason;
    final feedback = _feedback.text.trim();
    final media = _media;
    setState(() => _saving = true);
    final saved = await context.saveWorkOrder(
      widget.id,
      (order, now) => order.returnForCorrection(
        reason: reason,
        feedback: feedback,
        media: media,
        assignee: assignee.name,
        assigneeId: assignee.uid,
        at: now,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) return;
    _toast(context, 'Returned to ${assignee.name} · editing unlocked');
    context.go(AppRoutes.supervisorReview);
  }

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) => TeamBuilder(
        builder: (context, team) {
          final text = Theme.of(context).textTheme;
          // The current technician first, then the rest of the team.
          final current =
              team.where((m) => m.uid == order.assigneeId).firstOrNull ??
              team.firstOrNull;
          final people = [
            ?current,
            for (final member in team)
              if (member != current) member,
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
                      max: 4,
                      onChanged: (media) => _media = media,
                    ),
                    if (people.isNotEmpty)
                      LabelledDropdown(
                        label: 'Return to',
                        options: [for (final m in people) m.name],
                        onChanged: (value) => _returnTo = people.firstWhere(
                          (m) => m.name == value,
                        ),
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
                      onPressed: _saving ? null : () => _submit(current),
                      child: Text(_saving ? 'Saving…' : 'Return work order'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(TeamMember person) async {
    final note = _note.text.trim();
    setState(() => _saving = true);
    final saved = await context.saveWorkOrder(
      widget.id,
      (order, now) => order.reassign(
        assignee: person.name,
        assigneeId: person.uid,
        at: now,
        note: note.isEmpty ? null : note,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) return;
    _toast(context, 'Assigned to ${person.name} · notification sent');
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
      builder: (context, order) => TeamBuilder(
        builder: (context, team) {
          final text = Theme.of(context).textTheme;
          final others = team.where((m) => m.uid != order.assigneeId).toList();
          final selected =
              others.where((m) => m.uid == _selected).firstOrNull ??
              others.firstOrNull;
          return DetailPage(
            title: order.assignee == null ? 'Assign task' : 'Reassign task',
            children: [
              Text('Choose an available worker', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('${order.id} · ${order.title}', style: text.bodyMedium),
              const SizedBox(height: 12),
              InfoBanner(
                'Only workers assigned to '
                '${context.profileOf(AppRole.supervisor).facility.split(',').first} '
                'are shown.',
                tone: BannerTone.neutral,
              ),
              if (others.isEmpty)
                const EmptyListMessage('No one else is on this team yet.'),
              RadioGroup<String>(
                groupValue: selected?.uid,
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
                          value: worker.uid,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.trailing,
                          // The avatar sits in its own slot so the name and the
                          // role line up under each other.
                          secondary: InitialsAvatar(worker.initials),
                          title: Text(worker.name, style: text.titleSmall),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                ?worker.designation,
                                worker.onShift ? 'On site' : 'Off shift',
                              ].join(' · '),
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
                onPressed: selected == null || _saving
                    ? null
                    : () => _submit(selected),
                child: Text(
                  order.assignee == null
                      ? 'Assign & notify'
                      : 'Reassign & notify',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
