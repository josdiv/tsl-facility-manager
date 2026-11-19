import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/auth/domain/auth_repository.dart';
import 'package:tsl_facility_manager/features/auth/presentation/session_cubit.dart';
import 'package:tsl_facility_manager/features/notifications/domain/notifications.dart';
import 'package:tsl_facility_manager/features/profile/domain/user_profile.dart';

const _tech = UserProfile(
  uid: 'tech',
  name: 'Test Technician',
  phone: '',
  email: 'tech@example.com',
  facility: 'Test Facility',
);

/// Sign-out where the profile changes once more before Auth signs out, like
/// clocking out does.
class _Auth implements AuthRepository {
  final users = StreamController<UserProfile?>.broadcast();

  @override
  Stream<UserProfile?> watchUser() => users.stream;

  @override
  Future<void> signOut() async {
    users.add(_tech); // Late profile update.
    await Future<void>.delayed(Duration.zero);
    users.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Push implements PushService {
  final bound = <String>[];
  var unbound = 0;

  @override
  Future<void> bind(UserProfile user) async => bound.add(user.uid);

  @override
  Future<void> unbind() async => unbound++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'signing out never registers the device again for the person leaving',
    () async {
      final auth = _Auth();
      final push = _Push();
      final cubit = SessionCubit(auth, enforced: true, push: push);

      auth.users.add(_tech);
      await Future<void>.delayed(Duration.zero);
      expect(push.bound, ['tech']);

      await cubit.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(push.unbound, 1);
      expect(push.bound, ['tech']);
      expect(cubit.state.status, SessionStatus.signedOut);
      await cubit.close();
    },
  );
}
