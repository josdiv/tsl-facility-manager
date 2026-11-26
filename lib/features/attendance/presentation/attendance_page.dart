import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
import 'shift_actions.dart';

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
    if (!await confirmShiftChange(
      context,
      clockIn: clockIn,
      facility: _site?.name ?? user.facility,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (clockIn) {
        await attendance.clockIn(user, _fix!);
        messenger.showSnackBar(
          const SnackBar(content: Text('Shift started · GPS verified')),
        );
        // Staff start their shift with their tasks, supervisors with the
        // work waiting for review.
        router.go(afterClockInRoute(widget.role));
      } else {
        await attendance.clockOut(user, _fix!);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Shift ended')));
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
    final located = site != null && site.hasPosition;
    final verdict = !located || fix == null ? null : verdictFor(site, fix);
    final distance = !located || fix == null
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
        _GeofenceMap(
          inside: verdict == GpsVerdict.inside,
          site: site,
          fix: fix,
        ),
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
    Widget retry(String label) => OutlinedButton(
      onPressed: _checking ? null : _check,
      child: Text(label),
    );

    // Clocking out is checked like clocking in: at the facility, with a
    // real, precise enough reading.
    final verb = clockedIn ? 'clock out' : 'clock in';
    final running = clockedIn
        ? const [
            InfoBanner(
              'Your shift is running. Clock out at the facility before you '
              'leave.',
              icon: Icons.timer_outlined,
              tone: BannerTone.success,
            ),
          ]
        : const <Widget>[];
    return [...running, ..._gated(clockedIn, verb, verdict, distance, retry)];
  }

  List<Widget> _gated(
    bool clockedIn,
    String verb,
    GpsVerdict? verdict,
    int? distance,
    Widget Function(String label) retry,
  ) {
    final location = context.read<LocationService>();
    if (_site != null && !_site!.hasPosition) {
      return const [
        InfoBanner(
          'Your facility’s location hasn’t been set up yet, so attendance '
          'isn’t available. Ask your administrator to add it.',
          icon: Icons.edit_location_alt_outlined,
          tone: BannerTone.warning,
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
          InfoBanner(
            'Your phone’s location is turned off. Turn it on to $verb.',
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
        if (clockedIn)
          FilledButton(
            onPressed: _busy ? null : () => _clock(clockIn: false),
            child: const Text('Verify & clock out'),
          )
        else
          FilledButton(
            onPressed: _busy ? null : () => _clock(clockIn: true),
            child: const Text('Verify & clock in'),
          ),
      ],
      GpsVerdict.outside => [
        InfoBanner(
          '${clockedIn ? 'Clock-out' : 'Clock-in'} blocked: you are '
          '${distanceLabel(distance!)} away. Move '
          'within the '
          '${_site!.radiusM.round()} metre facility boundary and try again.',
          icon: Icons.location_off_outlined,
          tone: BannerTone.danger,
        ),
        retry('Check again'),
      ],
      GpsVerdict.mocked => [
        InfoBanner(
          'Your location appears to come from a location-faking app. Turn it '
          'off to $verb.',
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

/// The facility's boundary and the person's position on a Google map, when
/// the facility has a position. Otherwise, and in tests, a simple drawing.
class _GeofenceMap extends StatelessWidget {
  const _GeofenceMap({required this.inside, this.site, this.fix});

  final bool inside;
  final Site? site;
  final LocationFix? fix;

  /// Google Maps needs a platform view and, on iOS, a key set up in
  /// AppDelegate, which isn't done yet.
  static final _canShowMap =
      Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    final color = inside ? AppColors.teal : AppColors.danger;
    final site = this.site;
    return Semantics(
      label: inside
          ? 'Map: you are inside the geofence'
          : 'Map: you are not confirmed inside the geofence',
      child: _canShowMap && site != null && site.hasPosition
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: _SiteMap(site: site, fix: fix, color: color),
              ),
            )
          : _drawing(color),
    );
  }

  Widget _drawing(Color color) => Container(
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
  );
}

class _SiteMap extends StatefulWidget {
  const _SiteMap({required this.site, required this.fix, required this.color});

  final Site site;
  final LocationFix? fix;
  final Color color;

  @override
  State<_SiteMap> createState() => _SiteMapState();
}

class _SiteMapState extends State<_SiteMap> {
  GoogleMapController? _map;

  LatLng get _centre => LatLng(widget.site.latitude!, widget.site.longitude!);

  /// The boundary circle, plus the person when there's a reading.
  LatLngBounds get _bounds {
    final centre = _centre;
    final radius = widget.site.radiusM;
    final dLat = radius / 111320;
    final dLng = radius / (111320 * math.cos(centre.latitude * math.pi / 180));
    var south = centre.latitude - dLat, north = centre.latitude + dLat;
    var west = centre.longitude - dLng, east = centre.longitude + dLng;
    final fix = widget.fix;
    if (fix != null) {
      south = math.min(south, fix.latitude);
      north = math.max(north, fix.latitude);
      west = math.min(west, fix.longitude);
      east = math.max(east, fix.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  void _frame() =>
      _map?.animateCamera(CameraUpdate.newLatLngBounds(_bounds, 32));

  @override
  void didUpdateWidget(_SiteMap old) {
    super.didUpdateWidget(old);
    if (old.fix != widget.fix || old.site != widget.site) _frame();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fix = widget.fix;
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _centre, zoom: 17),
      onMapCreated: (controller) {
        _map = controller;
        // Wait a frame so the map knows its size before fitting the bounds.
        WidgetsBinding.instance.addPostFrameCallback((_) => _frame());
      },
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      circles: {
        Circle(
          circleId: const CircleId('site'),
          center: _centre,
          radius: widget.site.radiusM,
          fillColor: widget.color.withValues(alpha: 0.12),
          strokeColor: widget.color,
          strokeWidth: 2,
        ),
        if (fix != null)
          Circle(
            circleId: const CircleId('accuracy'),
            center: LatLng(fix.latitude, fix.longitude),
            radius: fix.accuracyM,
            fillColor: AppColors.primary.withValues(alpha: 0.10),
            strokeColor: AppColors.primary.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('site'),
          position: _centre,
          infoWindow: InfoWindow(title: widget.site.name),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        ),
        if (fix != null)
          Marker(
            markerId: const MarkerId('you'),
            position: LatLng(fix.latitude, fix.longitude),
            infoWindow: const InfoWindow(title: 'You'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
      },
    );
  }
}
