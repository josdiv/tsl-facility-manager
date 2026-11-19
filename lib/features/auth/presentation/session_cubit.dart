import '../../notifications/domain/notifications.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/auth_repository.dart';

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  SessionCubit(this._auth, {required bool enforced, PushService? push})
    : _push = push,
      super(
        SessionState(enforced ? SessionStatus.unknown : SessionStatus.sample),
      ) {
    if (enforced) {
      _subscription = _auth.watchUser().listen((user) {
        emit(
          user == null
              ? const SessionState(SessionStatus.signedOut)
              : SessionState(SessionStatus.signedIn, user),
        );
        // Register this device for the signed-in person's pushes. Not while
        // signing out: a late profile update (e.g. from clocking out) would
        // register the device again for the person leaving.
        if (user != null && !_signingOut) unawaited(_push?.bind(user));
      });
    }
  }

  final AuthRepository _auth;
  final PushService? _push;
  StreamSubscription<UserProfile?>? _subscription;
  var _signingOut = false;

  /// Signs out and, when sign-in is enforced, waits until the session has
  /// caught up, so the caller can navigate without the router bouncing it.
  Future<void> signOut() async {
    _signingOut = true;
    try {
      // While still signed in, so the device's token can be removed.
      await _push?.unbind();
      await _auth.signOut();
      if (state.status == SessionStatus.signedIn) {
        await stream
            .firstWhere((s) => s.status != SessionStatus.signedIn)
            .timeout(const Duration(seconds: 5), onTimeout: () => state);
      }
    } finally {
      _signingOut = false;
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
