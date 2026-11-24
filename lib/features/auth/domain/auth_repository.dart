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

  /// Emails a 6-digit code to a client, or to someone signing up as one.
  Future<void> sendEmailCode(String email);

  /// Checks the code from the email. A client is signed in and null is
  /// returned; for a new email it returns a sign-up ticket for
  /// [createClientAccount].
  Future<String?> verifyEmailCode(String email, String code);

  /// Creates a new client's account and signs them in.
  Future<void> createClientAccount({
    required String email,
    required String ticket,
    required String name,
    required String company,
    required String phone,
  });

  Future<void> sendPasswordReset(String email);

  /// Permanently deletes the signed-in client's account, then signs out.
  Future<void> deleteAccount();

  Future<void> signOut();

  /// Saves the editable parts of the signed-in user's profile.
  Future<void> updateProfile({
    required String name,
    required String phone,
    Facility? facility,
  });

  /// Every active facility, for a client to choose from. Clients can only
  /// report at the one they're standing in.
  Future<List<Facility>> facilityOptions();
}
