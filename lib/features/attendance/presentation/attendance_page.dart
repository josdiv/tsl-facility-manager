import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';

import '../../profile/presentation/profile_cubit.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/eyebrow.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/key_value_row.dart';
import '../../../core/widgets/page_frames.dart';

/// Which roles are on the clock. Sample data until GPS is connected.
class AttendanceCubit extends Cubit<Set<AppRole>> {
  AttendanceCubit() : super(const {});

  void clockIn(AppRole role) => emit({...state, role});

  void clockOut(AppRole role) => emit({...state}..remove(role));
}

/// What the device reports about the user's position.
enum GpsReading {
  inside('24 metres · Inside zone', '± 8 metres'),
  outside('245 metres · Outside zone', '± 8 metres'),
  weakSignal('Unknown', '± 90 metres'),
  permissionOff('Unavailable', 'Unavailable');

  const GpsReading(this.distance, this.accuracy);

  final String distance;
  final String accuracy;

  static GpsReading fromName(String? name) => values.firstWhere(
    (reading) => reading.name == name,
    orElse: () => inside,
  );
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({
    required this.role,
    this.reading = GpsReading.inside,
    this.isPreview = false,
    super.key,
  });

  final AppRole role;
  final GpsReading reading;

  /// Shows the page as a pushed screen, for the refused clock-in designs.
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[_AttendanceBody(role: role, reading: reading)];
    return isPreview
        ? DetailPage(title: 'GPS attendance', children: children)
        : TabPage(title: 'GPS attendance', role: role, children: children);
  }
}

class _AttendanceBody extends StatelessWidget {
  const _AttendanceBody({required this.role, required this.reading});

  final AppRole role;
  final GpsReading reading;

  @override
  Widget build(BuildContext context) {
    final canClockIn = reading == GpsReading.inside;
    // A refused reading always shows the refused state, never an active shift.
    final clockedIn =
        context.select<AttendanceCubit, bool>(
          (cubit) => cubit.state.contains(role),
        ) &&
        canClockIn;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Location-based attendance'),
        const SizedBox(height: 8),
        Text(
          clockedIn ? 'You’re on the clock' : 'Start your shift',
          style: text.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'You must be inside your assigned facility’s geofence.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        _GeofenceMap(inside: canClockIn),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.profileOf(role).facility, style: text.titleMedium),
              const SizedBox(height: 4),
              Text('12 Marina Road, Lagos Island', style: text.bodyMedium),
              const SizedBox(height: 4),
              const KeyValueRow('Allowed radius', '100 metres'),
              KeyValueRow(
                'Your distance',
                reading.distance,
                valueColor: canClockIn ? AppColors.success : AppColors.danger,
              ),
              KeyValueRow('GPS accuracy', reading.accuracy, divider: clockedIn),
              if (clockedIn)
                const KeyValueRow('Clocked in at', '08:02 AM', divider: false),
            ],
          ),
        ),
        ..._stateMessage(context, clockedIn),
      ],
    );
  }

  List<Widget> _stateMessage(BuildContext context, bool clockedIn) {
    final cubit = context.read<AttendanceCubit>();
    void clock(String message, VoidCallback action) {
      action();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    return switch (reading) {
      GpsReading.inside => [
        const InfoBanner(
          'Location verified. You are inside the facility boundary.',
          icon: Icons.check_circle_outline,
          tone: BannerTone.success,
        ),
        if (clockedIn)
          OutlinedButton(
            onPressed: () => clock('Shift ended', () => cubit.clockOut(role)),
            child: const Text('Clock out'),
          )
        else
          FilledButton(
            onPressed: () {
              clock('Shift started · GPS verified', () => cubit.clockIn(role));
              // Staff start their shift by picking up work.
              if (role == AppRole.staff) context.go(AppRoutes.staffTasks);
            },
            child: const Text('Verify & clock in'),
          ),
      ],
      GpsReading.outside => const [
        InfoBanner(
          'Clock-in blocked: you are 245m away. Move within the 100m facility '
          'boundary and try again.',
          icon: Icons.location_off_outlined,
          tone: BannerTone.danger,
        ),
        FilledButton(onPressed: null, child: Text('Verify & clock in')),
      ],
      GpsReading.weakSignal => [
        const InfoBanner(
          'GPS signal is too weak to confirm your location. Move near a window '
          'or outdoors, then try again.',
          icon: Icons.gps_not_fixed,
          tone: BannerTone.warning,
        ),
        OutlinedButton(onPressed: () {}, child: const Text('Try again')),
      ],
      GpsReading.permissionOff => [
        const InfoBanner(
          'Location permission is off. Attendance needs your location to '
          'confirm you are on site.',
          icon: Icons.location_disabled,
          tone: BannerTone.warning,
        ),
        FilledButton(onPressed: () {}, child: const Text('Open settings')),
      ],
    };
  }
}

class _GeofenceMap extends StatelessWidget {
  const _GeofenceMap({required this.inside});

  final bool inside;

  @override
  Widget build(BuildContext context) {
    final color = inside ? AppColors.teal : AppColors.danger;
    return Semantics(
      label: inside
          ? 'Map: you are inside the geofence'
          : 'Map: you are not confirmed inside the geofence',
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE3EEEC), Color(0xFFEDE7F0)],
          ),
        ),
        child: Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color),
            ),
            child: Icon(Icons.location_on, color: color, size: 32),
          ),
        ),
      ),
    );
  }
}
