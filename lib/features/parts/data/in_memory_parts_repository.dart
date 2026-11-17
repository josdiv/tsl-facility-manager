import 'dart:async';

import '../../profile/domain/user_profile.dart';
import '../domain/requisition.dart';

/// Sample stock and requests for tests and SAMPLE_DATA builds.
class InMemoryPartsRepository implements PartsRepository {
  InMemoryPartsRepository({DateTime? now}) {
    final at = now ?? DateTime.now();
    _requests.addAll([
      Requisition(
        ref: 'REQ-081',
        itemName: 'LED panel',
        quantity: 2,
        reason: 'Corridor lighting on floor 4',
        workOrderId: 'WO-1037',
        requestedAt: at.subtract(const Duration(days: 1)),
        status: RequisitionStatus.approved,
      ),
      Requisition(
        ref: 'REQ-079',
        itemName: 'Generator oil',
        quantity: 6,
        reason: 'Monthly service top-up',
        requestedAt: at.subtract(const Duration(days: 4)),
        status: RequisitionStatus.rejected,
        rejectionReason: 'Stock already issued for this month.',
      ),
    ]);
  }

  static const _stock = [
    StockItem(
      id: 'filters',
      name: 'HVAC air filter',
      quantity: 24,
      locationId: 'marina',
    ),
    StockItem(id: 'led', name: 'LED panel', quantity: 8, locationId: 'marina'),
    StockItem(
      id: 'oil',
      name: 'Generator oil',
      quantity: 6,
      locationId: 'marina',
    ),
  ];

  final _requests = <Requisition>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Requisition>> watchRequests(UserProfile user) async* {
    yield List.unmodifiable(_requests);
    yield* _changes.stream.map((_) => List.unmodifiable(_requests));
  }

  @override
  Stream<List<StockItem>> watchStock(String locationId) => Stream.value(_stock);

  @override
  Future<void> request(
    UserProfile user, {
    required StockItem item,
    required int quantity,
    required String reason,
    String? workOrderId,
  }) async {
    final next = _requests
        .map((r) => int.parse(r.ref.split('-').last))
        .fold(0, (a, b) => a > b ? a : b);
    _requests.insert(
      0,
      Requisition(
        ref: 'REQ-${(next + 1).toString().padLeft(3, '0')}',
        itemName: item.name,
        quantity: quantity,
        reason: reason,
        workOrderId: workOrderId,
        requestedAt: DateTime.now(),
      ),
    );
    _changes.add(null);
  }
}
