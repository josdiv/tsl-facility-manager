import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/session/app_role.dart';
import '../../../core/utils/streams.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/attendance.dart';

/// Who is on shift, and since when.
class AttendanceState extends Equatable {
  const AttendanceState([this.shifts = const {}]);

  final Map<AppRole, DateTime> shifts;

  bool contains(AppRole role) => shifts.containsKey(role);

  DateTime? since(AppRole role) => shifts[role];

  @override
  List<Object?> get props => [shifts];
}

/// Clocking in and out. With a [signedIn] stream it follows the signed-in
/// user's open shift in the backend; without one (sample data) it keeps the
/// shifts itself, for every role.
class AttendanceCubit extends Cubit<AttendanceState> {
  AttendanceCubit(this._repository, {Stream<UserProfile?>? signedIn})
    : _live = signedIn != null,
      super(const AttendanceState()) {
    _subscription = signedIn
        ?.switchMap(
          (user) => user == null
              ? Stream<AttendanceState>.value(const AttendanceState())
              : _repository
                    .watchShift(user)
                    .map(
                      (since) => AttendanceState(
                        since == null ? const {} : {user.role: since},
                      ),
                    ),
        )
        .listen(emit);
  }

  final AttendanceRepository _repository;
  final bool _live;
  StreamSubscription<AttendanceState>? _subscription;

  /// Throws [AttendanceFailure] when the server refuses.
  Future<void> clockIn(UserProfile user, LocationFix fix) async {
    await _repository.clockIn(user, fix);
    if (!_live)
      emit(AttendanceState({...state.shifts, user.role: DateTime.now()}));
  }

  Future<void> clockOut(UserProfile user, {LocationFix? fix}) async {
    await _repository.clockOut(user, fix: fix);
    if (!_live) {
      emit(AttendanceState({...state.shifts}..remove(user.role)));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
