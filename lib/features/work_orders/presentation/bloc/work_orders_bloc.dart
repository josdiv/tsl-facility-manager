import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/streams.dart';
import '../../../profile/domain/user_profile.dart';
import '../../domain/work_order.dart';
import '../../domain/work_order_repository.dart';

sealed class WorkOrdersEvent {
  const WorkOrdersEvent();
}

/// Starts following the signed-in user's orders.
class WorkOrdersRequested extends WorkOrdersEvent {
  const WorkOrdersRequested();
}

/// Applies a lifecycle change, such as starting or confirming, to one order.
class WorkOrderChanged extends WorkOrdersEvent {
  const WorkOrderChanged(this.id, this.change, {this.done});

  final String id;
  final WorkOrder Function(WorkOrder order, DateTime now) change;

  /// Completes with whether the change was saved. On failure the state's
  /// [WorkOrdersState.failure] says why.
  final Completer<bool>? done;
}

class IssueReported extends WorkOrdersEvent {
  const IssueReported(this.draft, this.client);

  final IssueDraft draft;
  final UserProfile client;
}

class WorkOrdersState extends Equatable {
  const WorkOrdersState({
    this.orders = const [],
    this.lastReportedId,
    this.failure,
    this.failureCount = 0,
  });

  final List<WorkOrder> orders;
  final String? lastReportedId;

  /// The last action that failed. [failureCount] grows with each one, so a
  /// listener can tell two identical failures apart.
  final WorkOrderFailure? failure;
  final int failureCount;

  WorkOrder? byId(String id) {
    for (final order in orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  /// Requests a client submitted.
  List<WorkOrder> submittedBy(String uid) =>
      orders.where((order) => order.submittedById == uid).toList();

  /// Work assigned to a technician.
  List<WorkOrder> assignedTo(String uid) =>
      orders.where((order) => order.assigneeId == uid).toList();

  List<WorkOrder> get awaitingReview =>
      orders.where((order) => order.isAwaitingReview).toList();

  /// Work a supervisor can still hand to someone else.
  List<WorkOrder> get teamActive => orders
      .where((order) => order.status.isActive && !order.isAwaitingReview)
      .toList();

  WorkOrdersState copyWith({
    List<WorkOrder>? orders,
    String? lastReportedId,
    WorkOrderFailure? failure,
  }) => WorkOrdersState(
    orders: orders ?? this.orders,
    lastReportedId: lastReportedId ?? this.lastReportedId,
    failure: failure ?? this.failure,
    failureCount: failure == null ? failureCount : failureCount + 1,
  );

  @override
  List<Object?> get props => [orders, lastReportedId, failure, failureCount];
}

class WorkOrdersBloc extends Bloc<WorkOrdersEvent, WorkOrdersState> {
  /// [scope] is the signed-in user, whose orders to follow. Sample data has
  /// no signed-in user, so it defaults to a single null: every order.
  WorkOrdersBloc(
    this._repository, {
    Stream<UserProfile?>? scope,
    DateTime Function()? clock,
  }) : _scope = scope ?? Stream.value(null),
       _clock = clock ?? DateTime.now,
       super(const WorkOrdersState()) {
    on<WorkOrdersRequested>(_onRequested);
    on<WorkOrderChanged>(_onChanged);
    on<IssueReported>(_onReported);
  }

  final WorkOrderRepository _repository;
  final Stream<UserProfile?> _scope;
  final DateTime Function() _clock;

  Future<void> _onRequested(
    WorkOrdersRequested event,
    Emitter<WorkOrdersState> emit,
  ) => emit.forEach(
    _scope.switchMap(_repository.watch),
    onData: (orders) => state.copyWith(orders: orders),
  );

  Future<void> _onChanged(
    WorkOrderChanged event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final order = state.byId(event.id);
    var saved = false;
    try {
      if (order == null) return;
      await _repository.update(order, event.change(order, _clock()));
      saved = true;
    } on WorkOrderFailure catch (failure) {
      emit(state.copyWith(failure: failure));
    } on StateError catch (error) {
      // The order moved on before this change, e.g. someone else returned it.
      emit(state.copyWith(failure: WorkOrderFailure(error.message)));
    } finally {
      event.done?.complete(saved);
    }
  }

  Future<void> _onReported(
    IssueReported event,
    Emitter<WorkOrdersState> emit,
  ) async {
    try {
      final id = await _repository.report(event.draft, event.client);
      emit(state.copyWith(lastReportedId: id));
    } on WorkOrderFailure catch (failure) {
      emit(state.copyWith(failure: failure));
    }
  }
}

/// Saving a work order change from a page.
extension SaveWorkOrder on BuildContext {
  /// Applies [change] to work order [id] and waits until it is saved.
  /// Returns false if it wasn't; the failure is in the bloc's state.
  Future<bool> saveWorkOrder(
    String id,
    WorkOrder Function(WorkOrder order, DateTime now) change,
  ) {
    final done = Completer<bool>();
    read<WorkOrdersBloc>().add(WorkOrderChanged(id, change, done: done));
    return done.future;
  }
}
