import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../profile/domain/user_profile.dart';

/// A position reading from the phone.
class LocationFix extends Equatable {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    this.isMocked = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyM;

  /// Android reports readings from fake-GPS apps. Always false on iOS.
  final bool isMocked;

  @override
  List<Object?> get props => [latitude, longitude, accuracyM, isMocked];
}

/// Why no position is available.
enum LocationProblem { permissionDenied, permanentlyDenied, serviceOff }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.problem);

  final LocationProblem problem;
}

/// The phone's location, behind an interface so tests never touch GPS.
abstract interface class LocationService {
  /// Asks for permission if needed. Throws [LocationUnavailable] when the
  /// app can't read the location.
  Future<void> ensurePermission();

  /// A current reading: a fresh fix if possible, a recent cached one, or a
  /// lower-accuracy one indoors.
  Future<LocationFix> currentFix();

  /// Opens the system screen that fixes [problem].
  Future<void> openSettings(LocationProblem problem);
}

/// The facility a person clocks in at.
class Site extends Equatable {
  const Site({
    required this.id,
    required this.name,
    required this.address,
    required this.radiusM,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String address;

  /// Null until the admin sets the facility's position.
  final double? latitude;
  final double? longitude;
  final double radiusM;

  bool get hasPosition => latitude != null && longitude != null;

  /// Metres from the centre of the site, on the Earth's surface. Only call
  /// when [hasPosition].
  double distanceTo(LocationFix fix) {
    final latitude = this.latitude!;
    final longitude = this.longitude!;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(fix.latitude - latitude);
    final dLng = rad(fix.longitude - longitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(fix.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371000 * math.asin(math.sqrt(h));
  }

  @override
  List<Object?> get props => [id, name, address, latitude, longitude, radiusM];
}

/// Readings less precise than this can't confirm someone is on site. The
/// clockIn function uses the same limit.
const maxAccuracyM = 50.0;

/// What a reading means for clocking in at [site].
enum GpsVerdict { inside, outside, weakSignal, mocked }

GpsVerdict verdictFor(Site site, LocationFix fix) {
  if (fix.isMocked) return GpsVerdict.mocked;
  final distance = site.distanceTo(fix);
  // Even a vague reading is decisive when its whole error margin is outside.
  if (distance - fix.accuracyM > site.radiusM) return GpsVerdict.outside;
  if (fix.accuracyM > maxAccuracyM) return GpsVerdict.weakSignal;
  return distance <= site.radiusM ? GpsVerdict.inside : GpsVerdict.outside;
}

/// "28 metres", or "3.2 km" once it's over a kilometre.
String distanceLabel(num metres) => metres < 1000
    ? '${metres.round()} metres'
    : '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km';

/// Why clocking in or out failed, in words the app can show.
class AttendanceFailure implements Exception {
  const AttendanceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AttendanceRepository {
  /// When [user]'s open shift started, or null when they're not clocked in.
  Stream<DateTime?> watchShift(UserProfile user);

  /// The facility [user] is assigned to.
  Future<Site?> siteFor(UserProfile user);

  /// Starts a shift. The server checks the distance again.
  Future<void> clockIn(UserProfile user, LocationFix fix);

  /// Ends the open shift, recording where if a reading is available.
  Future<void> clockOut(UserProfile user, {LocationFix? fix});
}
