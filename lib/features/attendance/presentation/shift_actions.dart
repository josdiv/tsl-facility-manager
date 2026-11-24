import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/info_banner.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../domain/attendance.dart';
import 'attendance_cubit.dart';

/// The attendance screen for [role].
String clockRoute(AppRole role) => role == AppRole.supervisor
    ? AppRoutes.supervisorClock
    : AppRoutes.staffClock;

/// Where a shift starts: staff pick up their tasks, supervisors their
/// review queue.
String afterClockInRoute(AppRole role) => role == AppRole.supervisor
    ? AppRoutes.supervisorReview
    : AppRoutes.staffTasks;

/// Asks before starting or ending a shift. True when confirmed.
Future<bool> confirmShiftChange(
  BuildContext context, {
  required bool clockIn,
  required String facility,
}) async {
  final now = TimeOfDay.now().format(context);
  final place = facility.split(',').first;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(clockIn ? 'Clock in?' : 'Clock out?'),
      content: Text(
        clockIn
            ? 'Start your shift at $place at $now.'
            : 'End your shift at $place at $now.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(clockIn ? 'Clock in' : 'Clock out'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The home screen's shift card for staff and supervisors: clock in (on the
/// attendance screen, which checks GPS) or clock out right here.
class ShiftCard extends StatefulWidget {
  const ShiftCard({required this.role, super.key});

  final AppRole role;

  @override
  State<ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<ShiftCard> {
  var _busy = false;

  Future<void> _clockOut() async {
    final user = context.read<ProfileCubit>().of(widget.role);
    final attendance = context.read<AttendanceCubit>();
    final location = context.read<LocationService>();
    final messenger = ScaffoldMessenger.of(context);
    if (!await confirmShiftChange(
      context,
      clockIn: false,
      facility: user.facility,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      // Where they clocked out, if the phone can say; ending the shift
      // doesn't depend on it.
      LocationFix? fix;
      try {
        await location.ensurePermission();
        fix = await location.currentFix().timeout(const Duration(seconds: 10));
      } on Object {
        fix = null;
      }
      await attendance.clockOut(user, fix: fix);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Shift ended')));
    } on AttendanceFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clockedIn = context.select<AttendanceCubit, bool>(
      (cubit) => cubit.state.contains(widget.role),
    );
    // Watched, so the facility appears once the profile has loaded.
    final me = context.profileOf(widget.role);
    final text = Theme.of(context).textTheme;
    return AppCard(
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
          if (clockedIn) ...[
            FilledButton(
              onPressed: _busy ? null : _clockOut,
              child: Text(_busy ? 'Clocking out…' : 'Clock out'),
            ),
            TextButton(
              onPressed: () => context.go(clockRoute(widget.role)),
              child: const Text('View attendance'),
            ),
          ] else
            FilledButton(
              onPressed: () => context.go(clockRoute(widget.role)),
              child: const Text('Clock in with GPS'),
            ),
        ],
      ),
    );
  }
}

/// Whether [role] is clocked in. Staff and supervisors must be, before they
/// act on any task.
bool isOnShift(BuildContext context, AppRole role) => context
    .select<AttendanceCubit, bool>((cubit) => cubit.state.contains(role));

/// Shown on a task while its staff member or supervisor is off shift; every
/// action on the task stays disabled until they clock in.
class ClockInFirst extends StatelessWidget {
  const ClockInFirst({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          'Clock in with GPS before you work on this task.',
          icon: Icons.location_on_outlined,
          tone: BannerTone.warning,
        ),
        OutlinedButton(
          onPressed: () => context.go(clockRoute(role)),
          child: const Text('Go to clock in'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
