import 'work_order.dart';

abstract interface class WorkOrderRepository {
  Future<List<WorkOrder>> getAll();

  /// Inserts the order, or replaces the existing order with the same id.
  Future<void> save(WorkOrder order);

  /// The next free work order reference, such as `WO-1049`.
  Future<String> nextId();
}
