import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profile/domain/user_profile.dart';
import '../domain/auth_repository.dart';

enum SessionStatus {
  /// Sample data: no sign-in is enforced.
  sample,

  /// Waiting for Firebase to say who, if anyone, is signed in.
  unknown,
  signedOut,
  signedIn,
}

class SessionState extends Equatable {
  const SessionState(this.status, [this.user]);

  final SessionStatus status;
  final UserProfile? user;

  @override
  List<Object?> get props => [status, user];
}

/// Who is signed in. The router follows this to guard screens.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth, {required bool enforced})
    : super(
        SessionState(enforced ? SessionStatus.unknown : SessionStatus.sample),
      ) {
    if (enforced) {
      _subscription = _auth.watchUser().listen(
        (user) => emit(
          user == null
              ? const SessionState(SessionStatus.signedOut)
              : SessionState(SessionStatus.signedIn, user),
        ),
      );
    }
  }

  final AuthRepository _auth;
  StreamSubscription<UserProfile?>? _subscription;

  /// Signs out and, when sign-in is enforced, waits until the session has
  /// caught up, so the caller can navigate without the router bouncing it.
  Future<void> signOut() async {
    await _auth.signOut();
    if (state.status == SessionStatus.signedIn) {
      await stream
          .firstWhere((s) => s.status != SessionStatus.signedIn)
          .timeout(const Duration(seconds: 5), onTimeout: () => state);
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
