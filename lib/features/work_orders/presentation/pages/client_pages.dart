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
import '../../../../core/widgets/progress_timeline.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../attendance/domain/attendance.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../profile/presentation/profile_cubit.dart';
import '../../data/sample_work_orders.dart';
import '../../domain/work_order.dart';
import '../../domain/work_order_repository.dart';
import '../bloc/work_orders_bloc.dart';
import '../widgets/work_order_card.dart';
import '../widgets/work_order_scope.dart';
import '../widgets/inspection_card.dart';

class ClientHomePage extends StatelessWidget {
  const ClientHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.profileOf(AppRole.client).uid;
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.submittedBy(uid),
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
    final uid = context.profileOf(AppRole.client).uid;
    final orders = context.select<WorkOrdersBloc, List<WorkOrder>>(
      (bloc) => bloc.state.submittedBy(uid),
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
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  var _facilities = const <Facility>[];

  /// What the issue is about: equipment (with its zone in front) or a zone.
  var _targets = const <_ReportTarget>[];
  Facility? _location;
  _ReportTarget? _target;
  var _targetsLoading = false;

  /// Where the phone is, once it can say. Facilities are then listed
  /// nearest first.
  LocationFix? _here;
  var _pickedByHand = false;
  var _media = const <String>[];
  var _formVersion = 0;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _loadFacilities();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Starts on the facility the client chose in their profile, then on the
  /// nearest one once the phone knows where it is. Clients see every
  /// facility but can only report at the one they're in.
  Future<void> _loadFacilities() async {
    final profiles = context.read<ProfileCubit>();
    final location = context.read<LocationService>();
    final facilities = await profiles.facilityOptions();
    if (!mounted) return;
    final chosen = profiles.of(AppRole.client).locationId;
    setState(() => _facilities = facilities);
    await _pickLocation(
      facilities.where((f) => f.id == chosen).firstOrNull ??
          facilities.firstOrNull,
    );

    LocationFix? fix;
    try {
      await location.ensurePermission();
      fix = await location.currentFix().timeout(const Duration(seconds: 15));
    } on Object {
      return; // Sending the report asks again, and explains what's wrong.
    }
    if (!mounted) return;
    final here = fix;
    double away(Facility f) => f.hasPosition
        ? f.distanceFrom(here.latitude, here.longitude)
        : double.infinity;
    final nearest = [...facilities]..sort((a, b) => away(a).compareTo(away(b)));
    setState(() {
      _here = here;
      _facilities = nearest;
    });
    final closest = nearest.firstOrNull;
    if (!_pickedByHand && closest != null && closest.hasPosition) {
      await _pickLocation(closest);
    }
  }

  /// Whether the client can report at [facility] from where they are.
  Widget? _distanceNote(Facility facility, TextTheme text) {
    final here = _here;
    if (here == null) return null;
    if (!facility.hasPosition) {
      return Text(
        '${facility.name} has no map position yet, so reports can’t be '
        'checked there.',
        style: text.bodySmall?.copyWith(color: AppColors.danger),
      );
    }
    final distance = facility.distanceFrom(here.latitude, here.longitude);
    if (distance <= facility.radiusM) {
      return Text(
        'You’re at ${facility.name}.',
        style: text.bodySmall?.copyWith(color: AppColors.success),
      );
    }
    return Text(
      'You’re ${distanceLabel(distance)} from ${facility.name}. You can only '
      'report an issue while you’re at the facility.',
      style: text.bodySmall?.copyWith(color: AppColors.danger),
    );
  }

  Future<void> _pickLocation(Facility? location) async {
    setState(() {
      _location = location;
      _targets = const [];
      _target = null;
      _targetsLoading = location != null;
    });
    if (location == null) return;
    final repository = context.read<WorkOrderRepository>();
    final (zones, assets) = await (
      repository.zones(location.id),
      repository.assets(location.id),
    ).wait;
    if (!mounted || _location != location) return;
    final targets = _ReportTarget.forFacility(zones, assets);
    setState(() {
      _targets = targets;
      _target = targets.firstOrNull;
      _targetsLoading = false;
    });
  }

  void _submit() {
    if (_sending || !_form.currentState!.validate()) return;
    final location = _location;
    final target = _target;
    // A facility without zones or equipment takes reports for the whole site.
    if (location == null ||
        _targetsLoading ||
        (target == null && _targets.isNotEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a location and zone first.')),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _sending = true);
    context.read<WorkOrdersBloc>().add(
      IssueReported(
        IssueDraft(
          title: _title.text.trim(),
          description: _description.text.trim(),
          location: location,
          zone: target?.zone,
          asset: target?.asset,
          media: _media,
        ),
        context.read<ProfileCubit>().of(AppRole.client),
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
      _sending = false;
      _media = const [];
      _formVersion++;
    });
    // Open it from the requests tab, so back goes to the list rather than
    // to a fresh form.
    final router = GoRouter.of(context);
    router.go(AppRoutes.clientRequests);
    router.push(AppRoutes.clientRequest(id));
  }

  void _onFailed(BuildContext context, WorkOrdersState state) {
    if (!_sending) return;
    setState(() => _sending = false);
    final failure = state.failure!;
    if (failure.code == 'monthly-limit') {
      context.push(AppRoutes.previewLimit);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MultiBlocListener(
      listeners: [
        BlocListener<WorkOrdersBloc, WorkOrdersState>(
          listenWhen: (before, after) =>
              after.lastReportedId != before.lastReportedId,
          listener: _onReported,
        ),
        BlocListener<WorkOrdersBloc, WorkOrdersState>(
          listenWhen: (before, after) =>
              after.failureCount != before.failureCount,
          listener: _onFailed,
        ),
      ],
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
                if (_facilities.isNotEmpty)
                  LabelledDropdown(
                    // Starts again on the nearest once the phone's position
                    // reorders the list.
                    key: ValueKey(_here),
                    label: 'Location',
                    options: [for (final f in _facilities) f.name],
                    initialValue: _location?.name,
                    onChanged: (value) {
                      _pickedByHand = true;
                      _pickLocation(
                        _facilities.firstWhere((f) => f.name == value),
                      );
                    },
                  ),
                if (_location case final location?)
                  if (_distanceNote(location, text) case final note?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: note,
                    ),
                if (_targets.isNotEmpty)
                  LabelledDropdown(
                    // A new location brings its own list, so start afresh.
                    key: ValueKey(_location),
                    label: _targets.any((t) => t.asset != null)
                        ? 'Asset / zone'
                        : 'Building / zone',
                    options: [for (final t in _targets) t.label],
                    onChanged: (value) =>
                        _target = _targets.firstWhere((t) => t.label == value),
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
                  max: 4,
                  onChanged: (media) => _media = media,
                ),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? 'Sending…' : 'Submit issue'),
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
              [
                order.id,
                if (order.history.firstOrNull case final first?)
                  'Submitted ${dateTimeLabel(first.at, now)}',
              ].join(' · '),
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
                  KeyValueRow('Location', order.place),
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
            // The technician's proof of work; the supervisor's inspection
            // photos are in the inspection card.
            if (order.workMedia.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Work photos', style: text.titleMedium),
                    if (order.workNote case final note? when note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(note, style: text.bodyMedium),
                      ),
                    const SizedBox(height: 12),
                    MediaGrid(order.workMedia),
                  ],
                ),
              ),
            InspectionCard(order),
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

/// One choice in the report form's "Asset / zone" list.
class _ReportTarget {
  const _ReportTarget(this.label, {this.zone, this.asset});

  final String label;
  final Zone? zone;
  final Asset? asset;

  /// A facility's equipment, each with its zone in front ("Canteen Block ·
  /// Air Conditioner"), then an "Other issue" choice per zone for faults
  /// that aren't about a piece of equipment. Without equipment, just the
  /// zones, as before.
  static List<_ReportTarget> forFacility(List<Zone> zones, List<Asset> assets) {
    if (assets.isEmpty) {
      return [for (final zone in zones) _ReportTarget(zone.name, zone: zone)];
    }
    String place(Zone? zone) =>
        zone == null || zone.name.isEmpty ? 'General' : zone.name;
    final sorted = [...assets]
      ..sort((a, b) {
        final byZone = place(a.zone).compareTo(place(b.zone));
        return byZone != 0 ? byZone : a.name.compareTo(b.name);
      });
    final targets = <_ReportTarget>[];
    final used = <String>{};
    for (final asset in sorted) {
      var label = '${place(asset.zone)} · ${asset.name}';
      // Two identical items in one zone stay apart by their reference.
      if (!used.add(label)) {
        label = '$label (${asset.id})';
        used.add(label);
      }
      targets.add(_ReportTarget(label, zone: asset.zone, asset: asset));
    }
    if (zones.isEmpty) {
      targets.add(const _ReportTarget('Other issue'));
    } else {
      for (final zone in zones) {
        targets.add(_ReportTarget('${zone.name} · Other issue', zone: zone));
      }
    }
    return targets;
  }
}
