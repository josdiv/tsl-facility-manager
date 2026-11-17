import '../../profile/domain/user_profile.dart';
import '../domain/auth_repository.dart';

/// Sample mode: every sign-in works and nobody is tracked as signed in, so
/// each role's screens can be opened directly, as before Firebase.
class SampleAuthRepository implements AuthRepository {
  @override
  Stream<UserProfile?> watchUser() => const Stream.empty();

  @override
  Future<void> signInWithPassword(String email, String password) async {}

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> verifyEmailCode(String email, String code) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updateProfile({
    required String name,
    required String phone,
    Facility? facility,
  }) async {}

  @override
  Future<List<Facility>> facilityOptions() async => sampleFacilityOptions;
}
