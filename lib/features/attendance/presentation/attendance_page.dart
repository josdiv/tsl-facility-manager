import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/eyebrow.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/key_value_row.dart';
import '../../../core/widgets/page_frames.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../domain/attendance.dart';
import 'attendance_cubit.dart';

export 'attendance_cubit.dart';

/// Fixed readings for reviewing the refused clock-in designs at
/// /preview/gps/{state}. The real screen reads the phone's GPS.
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

  /// Only used by previews.
  final GpsReading reading;

  /// Shows a fixed [reading] as a pushed screen, for the refused designs.
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    if (isPreview) {
      return DetailPage(
        title: 'GPS attendance',
        children: [_PreviewBody(reading: reading)],
      );
    }
    return TabPage(
      title: 'GPS attendance',
      role: role,
      children: [_LiveAttendance(role: role)],
    );
  }
}

class _LiveAttendance extends StatefulWidget {
  const _LiveAttendance({required this.role});

  final AppRole role;

  @override
  State<_LiveAttendance> createState() => _LiveAttendanceState();
}

class _LiveAttendanceState extends State<_LiveAttendance> {
  Site? _site;
  LocationFix? _fix;
  LocationProblem? _problem;
  var _checking = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<ProfileCubit>().of(widget.role);
    final site = await context.read<AttendanceRepository>().siteFor(user);
    if (!mounted) return;
    setState(() => _site = site);
    await _check();
  }

  /// Reads the phone's position.
  Future<void> _check() async {
    final location = context.read<LocationService>();
    setState(() {
      _checking = true;
      _problem = null;
    });
    try {
      await location.ensurePermission();
      final fix = await location.currentFix();
      if (mounted) setState(() => _fix = fix);
    } on LocationUnavailable catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    } on Object {
      // No reading in time: treat it as a weak signal.
      if (mounted) setState(() => _fix = null);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _clock({required bool clockIn}) async {
    final user = context.read<ProfileCubit>().of(widget.role);
    final attendance = context.read<AttendanceCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      if (clockIn) {
        await attendance.clockIn(user, _fix!);
        messenger.showSnackBar(
          const SnackBar(content: Text('Shift started · GPS verified')),
        );
        // Staff start their shift by picking up work.
        if (widget.role == AppRole.staff) router.go(AppRoutes.staffTasks);
      } else {
        await attendance.clockOut(user, fix: _fix);
        messenger.showSnackBar(const SnackBar(content: Text('Shift ended')));
      }
    } on AttendanceFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final since = context.select<AttendanceCubit, DateTime?>(
      (cubit) => cubit.state.since(widget.role),
    );
    final clockedIn = since != null;
    final site = _site;
    final fix = _fix;
    final verdict = site == null || fix == null ? null : verdictFor(site, fix);
    final distance = site == null || fix == null
        ? null
        : site.distanceTo(fix).round();
    final text = Theme.of(context).textTheme;
    final distanceText = _checking
        ? 'Checking…'
        : distance == null
        ? 'Unavailable'
        : '${distanceLabel(distance)} · '
              '${switch (verdict) {
                GpsVerdict.inside => 'Inside zone',
                GpsVerdict.outside => 'Outside zone',
                _ => 'Uncertain',
              }}';

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
        _GeofenceMap(inside: verdict == GpsVerdict.inside),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(site?.name ?? 'Your facility', style: text.titleMedium),
              if (site != null) ...[
                const SizedBox(height: 4),
                Text(site.address, style: text.bodyMedium),
              ],
              const SizedBox(height: 4),
              KeyValueRow(
                'Allowed radius',
                site == null ? '—' : '${site.radiusM.round()} metres',
              ),
              KeyValueRow(
                'Your distance',
                distanceText,
                valueColor: switch (verdict) {
                  GpsVerdict.inside => AppColors.success,
                  GpsVerdict.outside || GpsVerdict.mocked => AppColors.danger,
                  _ => AppColors.warning,
                },
              ),
              KeyValueRow(
                'GPS accuracy',
                fix == null ? '—' : '± ${fix.accuracyM.round()} metres',
                divider: clockedIn,
              ),
              if (clockedIn)
                KeyValueRow(
                  'Clocked in at',
                  TimeOfDay.fromDateTime(since).format(context),
                  divider: false,
                ),
            ],
          ),
        ),
        ..._actions(clockedIn, verdict, distance),
      ],
    );
  }

  List<Widget> _actions(bool clockedIn, GpsVerdict? verdict, int? distance) {
    final location = context.read<LocationService>();
    Widget retry(String label) => OutlinedButton(
      onPressed: _checking ? null : _check,
      child: Text(label),
    );

    if (clockedIn) {
      return [
        const InfoBanner(
          'Your shift is running. Clock out when you leave the facility.',
          icon: Icons.timer_outlined,
          tone: BannerTone.success,
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _clock(clockIn: false),
          child: const Text('Clock out'),
        ),
      ];
    }
    if (_checking) {
      return const [
        InfoBanner(
          'Finding your location…',
          icon: Icons.my_location,
          tone: BannerTone.neutral,
        ),
      ];
    }
    switch (_problem) {
      case LocationProblem.permissionDenied:
        return [
          const InfoBanner(
            'Location permission is off. Attendance needs your location to '
            'confirm you are on site.',
            icon: Icons.location_disabled,
            tone: BannerTone.warning,
          ),
          FilledButton(onPressed: _check, child: const Text('Allow location')),
        ];
      case LocationProblem.permanentlyDenied:
        return [
          const InfoBanner(
            'Location permission is off. Turn it on for TSL Facility Manager '
            'in your phone’s settings, then come back.',
            icon: Icons.location_disabled,
            tone: BannerTone.warning,
          ),
          FilledButton(
            onPressed: () =>
                location.openSettings(LocationProblem.permanentlyDenied),
            child: const Text('Open settings'),
          ),
          const SizedBox(height: 8),
          retry('Try again'),
        ];
      case LocationProblem.serviceOff:
        return [
          const InfoBanner(
            'Your phone’s location is turned off. Turn it on to clock in.',
            icon: Icons.location_off_outlined,
            tone: BannerTone.warning,
          ),
          FilledButton(
            onPressed: () => location.openSettings(LocationProblem.serviceOff),
            child: const Text('Turn on location'),
          ),
          const SizedBox(height: 8),
          retry('Try again'),
        ];
      case null:
        break;
    }
    return switch (verdict) {
      GpsVerdict.inside => [
        const InfoBanner(
          'Location verified. You are inside the facility boundary.',
          icon: Icons.check_circle_outline,
          tone: BannerTone.success,
        ),
        FilledButton(
          onPressed: _busy ? null : () => _clock(clockIn: true),
          child: const Text('Verify & clock in'),
        ),
      ],
      GpsVerdict.outside => [
        InfoBanner(
          'Clock-in blocked: you are ${distanceLabel(distance!)} away. Move '
          'within the '
          '${_site!.radiusM.round()} metre facility boundary and try again.',
          icon: Icons.location_off_outlined,
          tone: BannerTone.danger,
        ),
        retry('Check again'),
      ],
      GpsVerdict.mocked => [
        const InfoBanner(
          'Your location appears to come from a location-faking app. Turn it '
          'off to clock in.',
          icon: Icons.gpp_bad_outlined,
          tone: BannerTone.danger,
        ),
        retry('Check again'),
      ],
      GpsVerdict.weakSignal || null => [
        const InfoBanner(
          'GPS signal is too weak to confirm your location. Move near a window '
          'or outdoors, then try again.',
          icon: Icons.gps_not_fixed,
          tone: BannerTone.warning,
        ),
        retry('Try again'),
      ],
    };
  }
}

/// The fixed designs for refused clock-ins.
class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.reading});

  final GpsReading reading;

  @override
  Widget build(BuildContext context) {
    final inside = reading == GpsReading.inside;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Location-based attendance'),
        const SizedBox(height: 8),
        Text('Start your shift', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'You must be inside your assigned facility’s geofence.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        _GeofenceMap(inside: inside),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Marina Towers, Lagos', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('12 Marina Road, Lagos Island', style: text.bodyMedium),
              const SizedBox(height: 4),
              const KeyValueRow('Allowed radius', '100 metres'),
              KeyValueRow(
                'Your distance',
                reading.distance,
                valueColor: inside ? AppColors.success : AppColors.danger,
              ),
              KeyValueRow('GPS accuracy', reading.accuracy, divider: false),
            ],
          ),
        ),
        ...switch (reading) {
          GpsReading.inside => const [
            InfoBanner(
              'Location verified. You are inside the facility boundary.',
              icon: Icons.check_circle_outline,
              tone: BannerTone.success,
            ),
          ],
          GpsReading.outside => const [
            InfoBanner(
              'Clock-in blocked: you are 245m away. Move within the 100m '
              'facility boundary and try again.',
              icon: Icons.location_off_outlined,
              tone: BannerTone.danger,
            ),
            FilledButton(onPressed: null, child: Text('Verify & clock in')),
          ],
          GpsReading.weakSignal => const [
            InfoBanner(
              'GPS signal is too weak to confirm your location. Move near a '
              'window or outdoors, then try again.',
              icon: Icons.gps_not_fixed,
              tone: BannerTone.warning,
            ),
            OutlinedButton(onPressed: null, child: Text('Try again')),
          ],
          GpsReading.permissionOff => const [
            InfoBanner(
              'Location permission is off. Attendance needs your location to '
              'confirm you are on site.',
              icon: Icons.location_disabled,
              tone: BannerTone.warning,
            ),
            FilledButton(onPressed: null, child: Text('Open settings')),
          ],
        },
      ],
    );
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
