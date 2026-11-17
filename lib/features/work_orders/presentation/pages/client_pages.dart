import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/session/app_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/eyebrow.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/key_value_row.dart';
import '../../../../core/widgets/labelled_field.dart';
import '../../../../core/widgets/link_text_button.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../../core/widgets/page_frames.dart';
import '../../../profile/presentation/profile_cubit.dart';
import '../../../../core/widgets/progress_timeline.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../data/sample_work_orders.dart';
import '../../domain/work_order.dart';
import '../bloc/work_orders_bloc.dart';
import '../widgets/work_order_card.dart';
import '../widgets/work_order_scope.dart';

class ClientHomePage extends StatelessWidget {
  const ClientHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.submittedBy(sampleClient),
    );
    final text = Theme.of(context).textTheme;
    final active = orders.where((o) => o.status.isActive).length;
    final me = context.profileOf(AppRole.client);
    return TabPage(
      title: 'Home',
      role: AppRole.client,
      children: [
        Eyebrow(me.facility),
        const SizedBox(height: 8),
        Text('Hello, ${me.firstName} 👋', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'A better facility starts with a quick report.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Something needs fixing?',
                style: text.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Let our team know. We’ll take care of it.',
                style: TextStyle(color: Color(0xFFF7E8F2), fontSize: 14),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.clientReport),
                icon: const Icon(Icons.add),
                label: const Text('Report an issue'),
              ),
            ],
          ),
        ),
        StatRow(
          first: StatTile(
            icon: Icons.pending_actions,
            label: 'Active requests',
            value: '$active',
            caption: 'We’re on it',
          ),
          second: StatTile(
            icon: Icons.task_alt,
            label: 'Resolved',
            value: '${orders.length - active}',
            caption: 'This year',
            iconColor: AppColors.teal,
            iconBackground: AppColors.successSoft,
          ),
        ),
        SectionHeader(
          'Your latest requests',
          trailing: LinkTextButton(
            'View all',
            onPressed: () => context.go(AppRoutes.clientRequests),
          ),
        ),
        for (final order in orders.take(3))
          WorkOrderCard(
            order: order,
            clientView: true,
            actionLabel: 'Track',
            onTap: () => context.push(AppRoutes.clientRequest(order.id)),
          ),
      ],
    );
  }
}

class MyRequestsPage extends StatelessWidget {
  const MyRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.submittedBy(sampleClient),
    );
    final active = orders.where((o) => o.status.isActive).toList();
    final resolved = orders.where((o) => !o.status.isActive).toList();
    Widget list(List<WorkOrder> items) => items.isEmpty
        ? const EmptyListMessage('No requests here yet.')
        : ListView(
            padding: pagePadding,
            children: [
              for (final order in items)
                WorkOrderCard(
                  order: order,
                  clientView: true,
                  actionLabel: 'Track',
                  onTap: () => context.push(AppRoutes.clientRequest(order.id)),
                ),
            ],
          );

    return DefaultTabController(
      length: 3,
      child: TabPageFrame(
        title: 'My requests',
        role: AppRole.client,
        child: Column(
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  const Tab(text: 'All requests'),
                  Tab(text: 'Active (${active.length})'),
                  Tab(text: 'Resolved (${resolved.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [list(orders), list(active), list(resolved)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportIssuePage extends StatefulWidget {
  const ReportIssuePage({super.key});

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  /// Zones for each facility. Sample data until Firestore arrives.
  static const _zonesByLocation = {
    'Marina Towers, Lagos': ['Tower A · Floor 3', 'Reception', 'Car park'],
    'Cedar Court, Abuja': ['Main hall', 'Basement plant room', 'Car park'],
    'Harbour Point, Lekki': ['Lobby', 'Floor 2 offices', 'Rooftop'],
  };
  static final _locations = _zonesByLocation.keys.toList();

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  // Starts on the facility the client chose in their profile.
  late var _location = _defaultLocation();
  late var _zone = _zonesByLocation[_location]!.first;

  String _defaultLocation() {
    final facility = context.read<ProfileCubit>().of(AppRole.client).facility;
    return _zonesByLocation.containsKey(facility) ? facility : _locations.first;
  }

  var _media = const <String>[];
  var _formVersion = 0;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    context.read<WorkOrdersBloc>().add(
      IssueReported(
        title: _title.text.trim(),
        description: _description.text.trim(),
        location: _location,
        zone: _zone,
        media: _media,
        submittedBy: sampleClient,
      ),
    );
  }

  void _onReported(BuildContext context, WorkOrdersState state) {
    final id = state.lastReportedId;
    if (id == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Issue submitted · $id')));
    _title.clear();
    _description.clear();
    setState(() {
      _media = const [];
      _location = _defaultLocation();
      _zone = _zonesByLocation[_location]!.first;
      _formVersion++;
    });
    context.push(AppRoutes.clientRequest(id));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listenWhen: (before, after) =>
          after.lastReportedId != before.lastReportedId,
      listener: _onReported,
      child: TabPage(
        title: 'Report an issue',
        role: AppRole.client,
        children: [
          Form(
            key: _form,
            child: Column(
              key: ValueKey(_formVersion),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tell us what’s wrong', style: text.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Share the details so the right team can help.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 16),
                LabelledDropdown(
                  label: 'Location',
                  options: _locations,
                  initialValue: _location,
                  onChanged: (value) => setState(() {
                    _location = value;
                    _zone = _zonesByLocation[value]!.first;
                  }),
                ),
                LabelledDropdown(
                  // A new location brings its own zones, so start afresh.
                  key: ValueKey(_location),
                  label: 'Building / zone',
                  options: _zonesByLocation[_location]!,
                  onChanged: (value) => _zone = value,
                ),
                LabelledTextField(
                  label: 'Issue title',
                  hint: 'Air conditioning not cooling',
                  controller: _title,
                  validator: (value) =>
                      requiredText(value, 'Give the issue a short title'),
                ),
                LabelledTextField(
                  label: 'Description',
                  hint: 'What is happening, and where?',
                  controller: _description,
                  maxLines: 4,
                  validator: (value) =>
                      requiredText(value, 'Describe what is wrong'),
                ),
                MediaPickerField(
                  label: 'Photos',
                  onChanged: (media) => _media = media,
                ),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Submit issue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RequestTrackingPage extends StatelessWidget {
  const RequestTrackingPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: id,
      builder: (context, order) {
        final text = Theme.of(context).textTheme;
        final now = DateTime.now();
        final assignee = order.assignee;
        return DetailPage(
          title: 'Request tracking',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: WorkOrderBadges(order, clientView: true),
            ),
            const SizedBox(height: 10),
            Text(order.title, style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${order.id} · Submitted ${dateTimeLabel(order.history.first.at, now)}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (assignee == null)
                    Text(
                      'Waiting for the facility team to assign a technician.',
                      style: text.bodyMedium,
                    )
                  else
                    Row(
                      children: [
                        InitialsAvatar(_initials(assignee)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(assignee, style: text.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                'Assigned technician',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  KeyValueRow('Location', '${order.location} · ${order.zone}'),
                  KeyValueRow(
                    'Expected response',
                    dateTimeLabel(order.due, now),
                    divider: false,
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request progress', style: text.titleMedium),
                  const SizedBox(height: 14),
                  ProgressTimeline([
                    for (final event in order.history.where(_clientVisible))
                      TimelineStep(
                        event.title,
                        [dateTimeLabel(event.at, now), ?event.note].join(' · '),
                      ),
                    if (order.status.isActive)
                      const TimelineStep(
                        'Supervisor confirmation',
                        'Awaiting completed work',
                        done: false,
                      ),
                  ]),
                ],
              ),
            ),
            if (order.reportMedia.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your photos', style: text.titleMedium),
                    const SizedBox(height: 12),
                    MediaGrid(order.reportMedia),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(AppRoutes.chat(AppRole.client, order.id)),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message facility team'),
            ),
          ],
        );
      },
    );
  }

  /// A correction request is between the supervisor and the technician.
  static bool _clientVisible(WorkOrderEvent event) =>
      event.title != 'Returned for correction';
}

String _initials(String name) => name
    .split(' ')
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0])
    .join();
