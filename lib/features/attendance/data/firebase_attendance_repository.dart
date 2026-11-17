import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/attendance.dart';

/// Shifts in `attendance`, written only by the clockIn and clockOut Cloud
/// Functions, which check the distance on the server.
class FirebaseAttendanceRepository implements AttendanceRepository {
  FirebaseAttendanceRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? appFirestore(),
       _functions = functions ?? appFunctions();

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Stream<DateTime?> watchShift(UserProfile user) => _db
      .collection('attendance')
      .where('userId', isEqualTo: user.uid)
      .where('status', isEqualTo: 'clocked_in')
      .limit(1)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return null;
        final at = snap.docs.first.data()['clockInAt'] as Timestamp?;
        // Just written and waiting for the server's time.
        return at?.toDate() ?? DateTime.now();
      });

  @override
  Future<Site?> siteFor(UserProfile user) async {
    final id = user.locationId;
    if (id == null) return null;
    final data = (await _db.doc('locations/$id').get()).data();
    if (data == null) return null;
    final geo = data['geo'] as GeoPoint;
    return Site(
      id: id,
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      latitude: geo.latitude,
      longitude: geo.longitude,
      radiusM: (data['radiusM'] as num?)?.toDouble() ?? 100,
    );
  }

  @override
  Future<void> clockIn(UserProfile user, LocationFix fix) =>
      _call('clockIn', _position(fix));

  @override
  Future<void> clockOut(UserProfile user, {LocationFix? fix}) =>
      _call('clockOut', fix == null ? {} : _position(fix));

  Map<String, Object> _position(LocationFix fix) => {
    'latitude': fix.latitude,
    'longitude': fix.longitude,
    'accuracyM': fix.accuracyM,
    'isMocked': fix.isMocked,
  };

  Future<void> _call(String name, Map<String, Object> data) async {
    try {
      await _functions.httpsCallable(name).call<Object?>(data);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? e.details as Map : const {};
      throw AttendanceFailure(switch (e.message) {
        'outside-geofence' =>
          'You’re ${details['distanceM'] is num ? distanceLabel(details['distanceM'] as num) : 'too far'} '
              'from the facility. Move within ${details['radiusM'] ?? 100} '
              'metres and try again.',
        'weak-signal' =>
          'Your GPS signal is too weak to confirm you’re on site. Move near '
              'a window or outdoors and try again.',
        'mock-location' =>
          'Your location appears to come from a location-faking app. Turn it '
              'off to clock in.',
        _ when e.code == 'unavailable' || e.code == 'internal' =>
          'We couldn’t reach the server. Check your connection and try again.',
        _ => e.message ?? 'That didn’t work. Please try again.',
      });
    }
  }
}
