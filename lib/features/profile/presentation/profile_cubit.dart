import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/session/app_role.dart';
import '../domain/user_profile.dart';

/// Each role's profile. Sample data until Firestore arrives.
class ProfileCubit extends Cubit<Map<AppRole, UserProfile>> {
  ProfileCubit() : super(sampleProfiles);

  UserProfile of(AppRole role) => state[role]!;

  /// Saves edits. A facility change is ignored for roles whose facility the
  /// admin assigns.
  void save(
    AppRole role, {
    required String name,
    required String phone,
    String? facility,
  }) {
    final current = of(role);
    emit({
      ...state,
      role: current.copyWith(
        name: name.trim(),
        phone: phone.trim(),
        facility: canChooseFacility(role) ? facility : null,
      ),
    });
  }
}
