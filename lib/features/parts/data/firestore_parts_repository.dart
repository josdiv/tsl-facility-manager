import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/requisition.dart';

/// Requests in `requisitions` and stock in `inventory`. The server numbers
/// requests; approval (and the stock change) goes through actionRequisition.
class FirestorePartsRepository implements PartsRepository {
  FirestorePartsRepository({
    required String? Function(String ref) workOrderDocId,
    FirebaseFirestore? firestore,
  }) : _docIdFor = workOrderDocId,
       _db = firestore ?? appFirestore();

  final String? Function(String ref) _docIdFor;
  final FirebaseFirestore _db;

  @override
  Stream<List<Requisition>> watchRequests(UserProfile user) => _db
      .collection('requisitions')
      .where('requestedById', isEqualTo: user.uid)
      .orderBy('requestedAt', descending: true)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            Requisition(
              ref: doc.data()['ref'] as String? ?? '',
              itemName: doc.data()['itemName'] as String? ?? '',
              quantity: (doc.data()['quantity'] as num?)?.toInt() ?? 0,
              reason: doc.data()['reason'] as String? ?? '',
              workOrderId: doc.data()['workOrderRef'] as String?,
              requestedAt:
                  (doc.data()['requestedAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              status: switch (doc.data()['status']) {
                'approved' => RequisitionStatus.approved,
                'rejected' => RequisitionStatus.rejected,
                _ => RequisitionStatus.pending,
              },
              rejectionReason: doc.data()['rejectionReason'] as String?,
            ),
        ],
      );

  @override
  Stream<List<StockItem>> watchStock(String locationId) => _db
      .collection('inventory')
      .where('locationId', isEqualTo: locationId)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            if (doc.data()['status'] != 'inactive')
              StockItem(
                id: doc.id,
                name: doc.data()['itemName'] as String? ?? '',
                quantity: (doc.data()['quantity'] as num?)?.toInt() ?? 0,
                locationId: locationId,
              ),
        ]..sort((a, b) => a.name.compareTo(b.name)),
      );

  @override
  Future<void> request(
    UserProfile user, {
    required StockItem item,
    required int quantity,
    required String reason,
    String? workOrderId,
  }) async {
    final now = FieldValue.serverTimestamp();
    final workOrderDocId = workOrderId == null ? null : _docIdFor(workOrderId);
    try {
      await _db.collection('requisitions').add({
        'type': 'out',
        'inventoryId': item.id,
        'itemName': item.name,
        'locationId': item.locationId,
        'workOrderId': workOrderDocId,
        'workOrderRef': workOrderDocId == null ? null : workOrderId,
        'quantity': quantity,
        'reason': reason,
        'requestedById': user.uid,
        'requestedByName': user.name,
        'requestedAt': now,
        'status': 'pending',
        'createdAt': now,
        'createdBy': user.uid,
        'updatedAt': now,
        'updatedBy': user.uid,
      });
    } on FirebaseException {
      throw const PartsFailure(
        'Your request couldn’t be sent. Check your connection and try again.',
      );
    }
  }
}
