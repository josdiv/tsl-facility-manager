import 'dart:async';

import '../../profile/domain/user_profile.dart';
import '../domain/attendance.dart';

/// Sample facility used by tests and SAMPLE_DATA builds.
const sampleSite = Site(
  id: 'marina',
  name: 'Marina Towers, Lagos',
  address: '12 Marina Road, Lagos Island',
  latitude: 6.4515,
  longitude: 3.3886,
  radiusM: 100,
);

/// Always 24 m from [sampleSite], with good accuracy.
class SampleLocationService implements LocationService {
  const SampleLocationService();

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<LocationFix> currentFix() async =>
      const LocationFix(latitude: 6.4517, longitude: 3.3887, accuracyM: 8);

  @override
  Future<void> openSettings(LocationProblem problem) async {}
}

/// Shifts kept in memory, one per account.
class InMemoryAttendanceRepository implements AttendanceRepository {
  final _shifts = <String, DateTime>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<DateTime?> watchShift(UserProfile user) async* {
    yield _shifts[user.uid];
    yield* _changes.stream.map((_) => _shifts[user.uid]);
  }

  @override
  Future<Site?> siteFor(UserProfile user) async => sampleSite;

  @override
  Future<void> clockIn(UserProfile user, LocationFix fix) async {
    _shifts[user.uid] = DateTime.now();
    _changes.add(null);
  }

  @override
  Future<void> clockOut(UserProfile user, LocationFix fix) async {
    _shifts.remove(user.uid);
    _changes.add(null);
  }
}
