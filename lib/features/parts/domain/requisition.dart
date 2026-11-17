import 'package:equatable/equatable.dart';

enum RequisitionStatus {
  pending('Pending approval'),
  approved('Approved'),
  rejected('Rejected');

  const RequisitionStatus(this.label);

  final String label;
}

/// A parts request from the field team. Matches `requisitions` in
/// docs/firestore-schema.md.
class Requisition extends Equatable {
  const Requisition({
    required this.ref,
    required this.itemName,
    required this.quantity,
    required this.reason,
    required this.requestedAt,
    this.workOrderId,
    this.status = RequisitionStatus.pending,
    this.rejectionReason,
  });

  final String ref;
  final String itemName;
  final int quantity;
  final String reason;
  final DateTime requestedAt;
  final String? workOrderId;
  final RequisitionStatus status;
  final String? rejectionReason;

  @override
  List<Object?> get props => [
    ref,
    itemName,
    quantity,
    reason,
    requestedAt,
    workOrderId,
    status,
    rejectionReason,
  ];
}
