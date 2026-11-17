import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/session/app_role.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/user_profile.dart';

/// Each role's profile.
///
/// Without an [AuthRepository] it holds editable sample profiles for every
/// role. With one, it holds the signed-in user's profile, kept in step with
/// `users/{uid}`, and saves changes there.
class ProfileCubit extends Cubit<Map<AppRole, UserProfile>> {
  ProfileCubit({AuthRepository? auth})
    : _auth = auth,
      super(auth == null ? sampleProfiles : const {}) {
    _subscription = auth?.watchUser().listen(
      (user) => emit(user == null ? const {} : {user.role: user}),
    );
  }

  final AuthRepository? _auth;
  StreamSubscription<UserProfile?>? _subscription;

  /// The profile for [role]. Blank while signing in or out.
  UserProfile of(AppRole role) =>
      state[role] ??
      UserProfile(name: '', phone: '', email: '', facility: '', role: role);

  /// Facilities the client may choose from.
  Future<List<Facility>> facilityOptions() =>
      _auth?.facilityOptions() ?? Future.value(sampleFacilityOptions);

  /// Saves edits. A facility change is ignored for roles whose facility the
  /// admin assigns. Throws [AuthFailure] when the change can't be saved.
  Future<void> save(
    AppRole role, {
    required String name,
    required String phone,
    String? facility,
    Facility? facilityOption,
  }) async {
    final current = of(role);
    final chosen = canChooseFacility(role)
        ? facilityOption ??
              sampleFacilityOptions.where((f) => f.name == facility).firstOrNull
        : null;
    final updated = current.copyWith(
      name: name.trim(),
      phone: phone.trim(),
      facility: chosen?.name,
      locationId: chosen?.id,
    );
    final auth = _auth;
    if (auth == null) {
      emit({...state, role: updated});
      return;
    }
    await auth.updateProfile(
      name: updated.name,
      phone: updated.phone,
      facility: chosen,
    );
    // The users/{uid} listener brings the saved profile back.
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

extension CurrentProfile on BuildContext {
  /// The profile shown on [role]'s screens, rebuilding when it changes.
  UserProfile profileOf(AppRole role) =>
      select<ProfileCubit, UserProfile>((cubit) => cubit.of(role));
}
