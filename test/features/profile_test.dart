import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/core/session/app_role.dart';
import 'package:tsl_facility_manager/core/widgets/labelled_field.dart';
import 'package:tsl_facility_manager/features/profile/domain/user_profile.dart';
import 'package:tsl_facility_manager/features/profile/presentation/profile_cubit.dart';

void main() {
  group('ProfileCubit', () {
    late ProfileCubit cubit;
    setUp(() => cubit = ProfileCubit());
    tearDown(() => cubit.close());

    test('saves a trimmed name and phone', () {
      cubit.save(AppRole.staff, name: '  Grace Eze ', phone: ' 0803 555 0100 ');
      expect(cubit.of(AppRole.staff).name, 'Grace Eze');
      expect(cubit.of(AppRole.staff).phone, '0803 555 0100');
    });

    test('a client can change facility', () {
      cubit.save(
        AppRole.client,
        name: 'Daniel Clarke',
        phone: '+234 803 555 0142',
        facility: 'Cedar Court, Abuja',
      );
      expect(cubit.of(AppRole.client).facility, 'Cedar Court, Abuja');
    });

    test('staff and supervisors cannot change their assigned facility', () {
      for (final role in [AppRole.staff, AppRole.supervisor]) {
        final before = cubit.of(role).facility;
        cubit.save(
          role,
          name: 'Someone',
          phone: '08035550100',
          facility: 'Cedar Court, Abuja',
        );
        expect(cubit.of(role).facility, before, reason: role.label);
      }
    });

    test('email never changes', () {
      final before = cubit.of(AppRole.client).email;
      cubit.save(AppRole.client, name: 'New Name', phone: '08035550100');
      expect(cubit.of(AppRole.client).email, before);
    });

    test('roles are independent', () {
      cubit.save(AppRole.staff, name: 'Grace Eze', phone: '08035550100');
      expect(cubit.of(AppRole.supervisor).name, 'Sarah James');
    });
  });

  test('initials use the first two names', () {
    UserProfile named(String name) =>
        UserProfile(name: name, phone: '', email: '', facility: '');
    expect(named('Emeka Okafor').initials, 'EO');
    expect(named('grace  ada eze').initials, 'GA');
    expect(named('Sarah').initials, 'S');
    expect(named('   ').initials, '?');
  });

  test('only clients choose their facility', () {
    expect(canChooseFacility(AppRole.client), isTrue);
    expect(canChooseFacility(AppRole.staff), isFalse);
    expect(canChooseFacility(AppRole.supervisor), isFalse);
  });

  test('phoneText accepts common formats and rejects junk', () {
    for (final ok in ['+234 803 555 0142', '08035550142', '0803-555-0142']) {
      expect(phoneText(ok), isNull, reason: ok);
    }
    for (final bad in ['', '12ab', '123', '+234 803 555 0142 9999 9']) {
      expect(phoneText(bad), isNotNull, reason: bad);
    }
  });
}
