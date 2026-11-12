import '../domain/work_order.dart';
import '../domain/work_order_repository.dart';
import 'sample_work_orders.dart';

/// Stands in for Firebase during the UI phase. Data resets on app restart.
class InMemoryWorkOrderRepository implements WorkOrderRepository {
  InMemoryWorkOrderRepository({List<WorkOrder>? seed, DateTime? now})
    : _orders = [...(seed ?? sampleWorkOrders(now ?? DateTime.now()))];

  final List<WorkOrder> _orders;

  @override
  Future<List<WorkOrder>> getAll() async => List.unmodifiable(_orders);

  @override
  Future<void> save(WorkOrder order) async {
    final index = _orders.indexWhere((existing) => existing.id == order.id);
    if (index == -1) {
      _orders.insert(0, order);
    } else {
      _orders[index] = order;
    }
  }

  @override
  Future<String> nextId() async {
    final highest = _orders
        .map((order) => int.parse(order.id.split('-').last))
        .fold(1048, (a, b) => a > b ? a : b);
    return 'WO-${highest + 1}';
  }
}
