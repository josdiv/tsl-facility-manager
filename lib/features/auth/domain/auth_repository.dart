import '../../profile/domain/user_profile.dart';

/// Why sign-in or an account action failed, in words the app can show.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;

  /// A machine-readable reason, such as `account-locked`, when the app shows a
  /// dedicated screen for it.
  final String? code;

  @override
  String toString() => message;
}

/// Who is signed in, and the ways to sign in and out.
abstract interface class AuthRepository {
  /// The signed-in user's profile, or null when nobody is signed in.
  /// Emits again whenever the profile changes.
  Stream<UserProfile?> watchUser();

  /// Staff and supervisors sign in with the password the admin set up.
  Future<void> signInWithPassword(String email, String password);

  /// Emails a 6-digit code to a client.
  Future<void> sendEmailCode(String email);

  /// Signs a client in with the code from their email.
  Future<void> verifyEmailCode(String email, String code);

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Saves the editable parts of the signed-in user's profile.
  Future<void> updateProfile({
    required String name,
    required String phone,
    Facility? facility,
  });

  /// Facilities the signed-in client may choose from.
  Future<List<Facility>> facilityOptions();
}
