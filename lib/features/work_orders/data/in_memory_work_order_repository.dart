import '../../profile/domain/user_profile.dart';
import '../domain/work_order.dart';
import '../domain/work_order_repository.dart';

import 'dart:async';

import 'sample_work_orders.dart';

/// Sample data for tests and SAMPLE_DATA builds. Resets on app restart.
class InMemoryWorkOrderRepository implements WorkOrderRepository {
  InMemoryWorkOrderRepository({List<WorkOrder>? seed, DateTime? now})
    : _orders = [...(seed ?? sampleWorkOrders(now ?? DateTime.now()))],
      _now = now;

  final List<WorkOrder> _orders;
  final DateTime? _now;
  final _changes = StreamController<List<WorkOrder>>.broadcast();

  static const _zones = {
    'marina': [
      Zone('marina-a3', 'Tower A · Floor 3'),
      Zone('marina-reception', 'Reception'),
      Zone('marina-carpark', 'Car park'),
    ],
    'cedar': [
      Zone('cedar-hall', 'Main hall'),
      Zone('cedar-basement', 'Basement plant room'),
      Zone('cedar-carpark', 'Car park'),
    ],
    'harbour': [
      Zone('harbour-lobby', 'Lobby'),
      Zone('harbour-f2', 'Floor 2 offices'),
      Zone('harbour-roof', 'Rooftop'),
    ],
  };

  static const team = [
    TeamMember(
      uid: 'emeka',
      name: 'Emeka Okafor',
      designation: 'HVAC technician',
      onShift: true,
    ),
    TeamMember(
      uid: 'tunde',
      name: 'Tunde Bakare',
      designation: 'Electrician',
      onShift: true,
    ),
    TeamMember(
      uid: 'david',
      name: 'David Adeyemi',
      designation: 'General maintenance',
      onShift: true,
    ),
    TeamMember(uid: 'grace', name: 'Grace Eze', designation: 'Safety officer'),
  ];

  List<WorkOrder> get _snapshot => List.unmodifiable(_orders);

  @override
  Stream<List<WorkOrder>> watch(UserProfile? user) async* {
    yield _snapshot;
    yield* _changes.stream;
  }

  @override
  Stream<List<WorkOrderEvent>> watchHistory(String id) async* {
    List<WorkOrderEvent> historyOf(List<WorkOrder> orders) =>
        orders.where((o) => o.id == id).firstOrNull?.history ?? const [];
    yield historyOf(_orders);
    yield* _changes.stream.map(historyOf);
  }

  @override
  Future<void> update(WorkOrder before, WorkOrder after) async {
    final index = _orders.indexWhere((o) => o.id == after.id);
    if (index == -1) {
      throw WorkOrderFailure('${after.id} no longer exists.');
    }
    _orders[index] = after;
    _changes.add(_snapshot);
  }

  @override
  Future<String> report(IssueDraft draft, UserProfile client) async {
    final now = _now ?? DateTime.now();
    final highest = _orders
        .map((order) => int.parse(order.id.split('-').last))
        .fold(1048, (a, b) => a > b ? a : b);
    final id = 'WO-${highest + 1}';
    _orders.insert(
      0,
      WorkOrder(
        id: id,
        title: draft.title,
        description: draft.description,
        type: WorkOrderType.client,
        status: WorkOrderStatus.open,
        location: draft.location.name,
        zone: draft.zone.name,
        locationId: draft.location.id,
        zoneId: draft.zone.id,
        due: now.add(const Duration(hours: 24)),
        submittedBy: client.name,
        submittedById: client.uid,
        reportMedia: draft.media,
        history: [WorkOrderEvent('Issue reported', now)],
      ),
    );
    _changes.add(_snapshot);
    return id;
  }

  @override
  Future<List<Zone>> zones(String locationId) async =>
      _zones[locationId] ?? const [];

  @override
  Stream<List<TeamMember>> watchTeam(String locationId) => Stream.value(team);
}
