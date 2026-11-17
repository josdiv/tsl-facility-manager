import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../../core/utils/streams.dart';
import '../../../core/session/app_role.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/auth_repository.dart';

/// Sign-in with Firebase Auth. Profiles come from `users/{uid}`.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? appFirestore(),
       _functions = functions ?? appFunctions();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.doc('users/$uid');

  @override
  Stream<UserProfile?> watchUser() => _auth.authStateChanges().switchMap(
    (user) => user == null
        ? Stream<UserProfile?>.value(null)
        : _userDoc(user.uid).snapshots().map((snap) {
            final profile = profileFromDoc(snap);
            // Deactivated, or an account type the app doesn't serve.
            if (profile == null) unawaited(_auth.signOut());
            return profile;
          }),
  );

  @override
  Future<void> signInWithPassword(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final profile = profileFromDoc(await _userDoc(result.user!.uid).get());
      if (profile == null || profile.role == AppRole.client) {
        await _auth.signOut();
        throw const AuthFailure(
          'This account can’t sign in here. Contact your administrator.',
        );
      }
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_authMessage(e.code));
    }
  }

  @override
  Future<void> sendEmailCode(String email) =>
      _call('sendEmailCode', {'email': email.trim()});

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    final result = await _call('verifyEmailCode', {
      'email': email.trim(),
      'code': code,
    });
    try {
      await _auth.signInWithCustomToken(result['token'] as String);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_authMessage(e.code));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      // Same answer whether or not the account exists.
      if (e.code != 'user-not-found') throw AuthFailure(_authMessage(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateProfile({
    required String name,
    required String phone,
    Facility? facility,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure('Please sign in again.');
    try {
      await _userDoc(uid).update({
        'name': name.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'locationId': ?facility?.id,
        'locationName': ?facility?.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } on FirebaseException {
      throw const AuthFailure('Your changes couldn’t be saved. Try again.');
    }
  }

  @override
  Future<List<Facility>> facilityOptions() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    final companyId = (await _userDoc(uid).get()).data()?['companyId'];
    if (companyId is! String) return const [];
    final company = (await _db.doc('companies/$companyId').get()).data();
    final ids = List<String>.from(company?['locationIds'] as List? ?? []);
    final locations = await Future.wait(
      ids.map((id) => _db.doc('locations/$id').get()),
    );
    return [
      for (final doc in locations)
        if (doc.exists) Facility(doc.id, doc.data()!['name'] as String),
    ];
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      return Map<String, dynamic>.from(result.data as Map? ?? {});
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? '';
      if (message == 'account-locked' || message == 'account-disabled') {
        throw AuthFailure(
          message == 'account-locked'
              ? 'Your company’s account is temporarily locked.'
              : 'Your company’s account is no longer active.',
          code: message,
        );
      }
      throw AuthFailure(
        e.code == 'unavailable' || e.code == 'internal'
            ? 'We couldn’t reach the server. Check your connection and try '
                  'again.'
            : message,
      );
    }
  }

  static String _authMessage(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => 'That email and password don’t match.',
    'user-disabled' => 'This account has been turned off.',
    'too-many-requests' => 'Too many tries. Wait a few minutes and try again.',
    'network-request-failed' =>
      'We couldn’t reach the server. Check your connection and try again.',
    _ => 'Sign-in failed. Please try again.',
  };
}

/// Maps `users/{uid}` to a profile. Null for missing, inactive or admin
/// accounts, which can't use the mobile app.
UserProfile? profileFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  if (data == null || data['status'] != 'active') return null;
  final role = switch (data['role']) {
    'client' => AppRole.client,
    'staff' => AppRole.staff,
    'supervisor' => AppRole.supervisor,
    _ => null,
  };
  if (role == null) return null;
  return UserProfile(
    uid: doc.id,
    role: role,
    name: data['name'] as String? ?? '',
    phone: data['phone'] as String? ?? '',
    email: data['email'] as String? ?? '',
    facility: data['locationName'] as String? ?? '',
    locationId: data['locationId'] as String?,
    companyId: data['companyId'] as String?,
    companyName: data['companyName'] as String?,
    designation: data['designation'] as String?,
  );
}
