import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/core/session/app_role.dart';
import 'package:tsl_facility_manager/core/utils/date_labels.dart';
import 'package:tsl_facility_manager/core/widgets/labelled_field.dart';
import 'package:tsl_facility_manager/features/attendance/data/sample_attendance.dart';
import 'package:tsl_facility_manager/features/attendance/domain/attendance.dart';
import 'package:tsl_facility_manager/features/attendance/presentation/attendance_page.dart';
import 'package:tsl_facility_manager/features/auth/presentation/login_pages.dart';
import 'package:tsl_facility_manager/features/parts/presentation/parts_request_page.dart';
import 'package:tsl_facility_manager/features/profile/domain/user_profile.dart';

void main() {
  group('dateTimeLabel', () {
    final now = DateTime(2026, 11, 5, 10);

    test('names nearby days', () {
      expect(dateTimeLabel(DateTime(2026, 11, 5, 12), now), 'Today, 12:00');
      expect(
        dateTimeLabel(DateTime(2026, 11, 6, 9, 5), now),
        'Tomorrow, 09:05',
      );
      expect(dateTimeLabel(DateTime(2026, 11, 4, 16), now), 'Yesterday, 16:00');
    });

    test('uses the date for anything further away', () {
      expect(dateTimeLabel(DateTime(2026, 11, 1, 8, 14), now), '01 Nov, 08:14');
    });
  });

  test('longDateLabel', () {
    expect(longDateLabel(DateTime(2026, 11, 5)), 'Thursday, 05 November');
  });

  test('greetingFor follows the time of day', () {
    expect(greetingFor(DateTime(2026, 11, 5, 9)), 'Morning');
    expect(greetingFor(DateTime(2026, 11, 5, 13)), 'Afternoon');
    expect(greetingFor(DateTime(2026, 11, 5, 19)), 'Evening');
  });

  test('field validators', () {
    expect(emailText('emeka@thickservices.com'), isNull);
    expect(emailText('not-an-email'), isNotNull);
    expect(emailText(''), isNotNull);
    expect(requiredText('  ', 'Needed'), 'Needed');
    expect(requiredText('value', 'Needed'), isNull);
  });

  test('staff credentials pick the role', () {
    expect(roleForStaffEmail('emeka@thickservices.com'), AppRole.staff);
    expect(roleForStaffEmail(' Sarah@thickservices.com'), AppRole.supervisor);
  });

  test('quantityError checks stock', () {
    expect(quantityError('2', 24), isNull);
    expect(quantityError('24', 24), isNull);
    expect(quantityError('25', 24), 'Only 24 in stock at this location');
    expect(quantityError('0', 24), isNotNull);
    expect(quantityError('abc', 24), isNotNull);
  });

  test('AttendanceCubit tracks each role separately in sample mode', () async {
    const fix = LocationFix(latitude: 6.4517, longitude: 3.3887, accuracyM: 8);
    final cubit = AttendanceCubit(InMemoryAttendanceRepository());
    await cubit.clockIn(sampleProfiles[AppRole.staff]!, fix);
    expect(cubit.state.contains(AppRole.staff), isTrue);
    await cubit.clockIn(sampleProfiles[AppRole.supervisor]!, fix);
    await cubit.clockOut(sampleProfiles[AppRole.staff]!);
    expect(cubit.state.shifts.keys, [AppRole.supervisor]);
    await cubit.close();
  });

  group('geofence verdict', () {
    LocationFix at(double lat, double lng, {double accuracy = 8}) =>
        LocationFix(latitude: lat, longitude: lng, accuracyM: accuracy);

    test('measures distance in metres', () {
      // 0.001 degrees of latitude is about 111 metres.
      expect(sampleSite.distanceTo(at(6.4525, 3.3886)), closeTo(111, 1));
    });

    test('distances read in metres, then kilometres', () {
      expect(distanceLabel(28), '28 metres');
      expect(distanceLabel(3240), '3.2 km');
      expect(distanceLabel(402096), '402 km');
    });

    test('inside, outside, weak signal and fake GPS', () {
      expect(verdictFor(sampleSite, at(6.4517, 3.3887)), GpsVerdict.inside);
      expect(verdictFor(sampleSite, at(6.4535, 3.3886)), GpsVerdict.outside);
      expect(
        verdictFor(sampleSite, at(6.4517, 3.3887, accuracy: 90)),
        GpsVerdict.weakSignal,
      );
      // Hundreds of kilometres away is "outside" however vague the reading.
      expect(
        verdictFor(sampleSite, at(9.0765, 7.3986, accuracy: 105)),
        GpsVerdict.outside,
      );
      expect(
        verdictFor(
          sampleSite,
          const LocationFix(
            latitude: 6.4517,
            longitude: 3.3887,
            accuracyM: 5,
            isMocked: true,
          ),
        ),
        GpsVerdict.mocked,
      );
    });
  });

  test('GpsReading falls back to inside for unknown names', () {
    expect(GpsReading.fromName('outside'), GpsReading.outside);
    expect(GpsReading.fromName('nonsense'), GpsReading.inside);
  });
}
