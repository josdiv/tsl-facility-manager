import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/work_order.dart';
import '../../domain/work_order_repository.dart';

sealed class WorkOrdersEvent {
  const WorkOrdersEvent();
}

class WorkOrdersRequested extends WorkOrdersEvent {
  const WorkOrdersRequested();
}

/// Applies a lifecycle change, such as starting or confirming, to one order.
class WorkOrderChanged extends WorkOrdersEvent {
  const WorkOrderChanged(this.id, this.change);

  final String id;
  final WorkOrder Function(WorkOrder order, DateTime now) change;
}

class IssueReported extends WorkOrdersEvent {
  const IssueReported({
    required this.title,
    required this.description,
    required this.location,
    required this.zone,
    required this.media,
    required this.submittedBy,
  });

  final String title;
  final String description;
  final String location;
  final String zone;
  final List<String> media;
  final String submittedBy;
}

class WorkOrdersState extends Equatable {
  const WorkOrdersState({this.orders = const [], this.lastReportedId});

  final List<WorkOrder> orders;
  final String? lastReportedId;

  WorkOrder? byId(String id) {
    for (final order in orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  List<WorkOrder> submittedBy(String name) =>
      orders.where((order) => order.submittedBy == name).toList();

  List<WorkOrder> assignedTo(String name) =>
      orders.where((order) => order.assignee == name).toList();

  List<WorkOrder> get awaitingReview =>
      orders.where((order) => order.isAwaitingReview).toList();

  /// Work a supervisor can still hand to someone else.
  List<WorkOrder> get teamActive => orders
      .where((order) => order.status.isActive && !order.isAwaitingReview)
      .toList();

  @override
  List<Object?> get props => [orders, lastReportedId];
}

class WorkOrdersBloc extends Bloc<WorkOrdersEvent, WorkOrdersState> {
  WorkOrdersBloc(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const WorkOrdersState()) {
    on<WorkOrdersRequested>(_onRequested);
    on<WorkOrderChanged>(_onChanged);
    on<IssueReported>(_onReported);
  }

  final WorkOrderRepository _repository;
  final DateTime Function() _clock;

  Future<void> _onRequested(
    WorkOrdersRequested event,
    Emitter<WorkOrdersState> emit,
  ) async {
    emit(WorkOrdersState(orders: await _repository.getAll()));
  }

  Future<void> _onChanged(
    WorkOrderChanged event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final order = state.byId(event.id);
    if (order == null) return;
    await _repository.save(event.change(order, _clock()));
    emit(WorkOrdersState(orders: await _repository.getAll()));
  }

  Future<void> _onReported(
    IssueReported event,
    Emitter<WorkOrdersState> emit,
  ) async {
    final now = _clock();
    final id = await _repository.nextId();
    await _repository.save(
      WorkOrder(
        id: id,
        title: event.title,
        description: event.description,
        type: WorkOrderType.client,
        status: WorkOrderStatus.open,
        location: event.location,
        zone: event.zone,
        due: now.add(const Duration(hours: 24)),
        submittedBy: event.submittedBy,
        reportMedia: event.media,
        history: [WorkOrderEvent('Issue reported', now)],
      ),
    );
    emit(
      WorkOrdersState(orders: await _repository.getAll(), lastReportedId: id),
    );
  }
}
