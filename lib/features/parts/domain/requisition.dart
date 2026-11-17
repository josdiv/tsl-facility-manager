import 'package:equatable/equatable.dart';

import '../../profile/domain/user_profile.dart';

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

  /// `REQ-1001` and so on. Empty until the server assigns it.
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

/// Stock of one item at a facility. Matches `inventory/{id}`.
class StockItem extends Equatable {
  const StockItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.locationId,
  });

  final String id;
  final String name;
  final int quantity;
  final String locationId;

  @override
  List<Object?> get props => [id, name, quantity, locationId];
}

/// Why a request couldn't be sent, in words the app can show.
class PartsFailure implements Exception {
  const PartsFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class PartsRepository {
  /// [user]'s requests, newest first.
  Stream<List<Requisition>> watchRequests(UserProfile user);

  /// Stock at a facility, by name.
  Stream<List<StockItem>> watchStock(String locationId);

  /// Asks the admin for [quantity] of [item], optionally for a work order
  /// (its reference, such as `WO-1048`).
  Future<void> request(
    UserProfile user, {
    required StockItem item,
    required int quantity,
    required String reason,
    String? workOrderId,
  });
}
