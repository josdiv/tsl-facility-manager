import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/requisition.dart';

/// The signed-in technician's parts requests, newest first. Sample data until
/// Firestore arrives.
class RequisitionsCubit extends Cubit<List<Requisition>> {
  RequisitionsCubit({DateTime? now}) : super(_sample(now ?? DateTime.now()));

  static List<Requisition> _sample(DateTime now) => [
    Requisition(
      ref: 'REQ-081',
      itemName: 'LED panel',
      quantity: 2,
      reason: 'Corridor lighting on floor 4',
      workOrderId: 'WO-1037',
      requestedAt: now.subtract(const Duration(days: 1)),
      status: RequisitionStatus.approved,
    ),
    Requisition(
      ref: 'REQ-079',
      itemName: 'Generator oil',
      quantity: 6,
      reason: 'Monthly service top-up',
      requestedAt: now.subtract(const Duration(days: 4)),
      status: RequisitionStatus.rejected,
      rejectionReason: 'Stock already issued for this month.',
    ),
  ];

  /// Adds a pending request and returns its reference.
  String submit({
    required String itemName,
    required int quantity,
    required String reason,
    String? workOrderId,
    DateTime? at,
  }) {
    final next = state
        .map((r) => int.parse(r.ref.split('-').last))
        .fold(0, (a, b) => a > b ? a : b);
    final ref = 'REQ-${(next + 1).toString().padLeft(3, '0')}';
    emit([
      Requisition(
        ref: ref,
        itemName: itemName,
        quantity: quantity,
        reason: reason,
        workOrderId: workOrderId,
        requestedAt: at ?? DateTime.now(),
      ),
      ...state,
    ]);
    return ref;
  }
}
