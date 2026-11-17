import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/notifications.dart';

/// `users/{uid}/notifications`, written by Cloud Functions. The app can only
/// mark them read.
class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? appFirestore();

  final FirebaseFirestore _db;

  @override
  Stream<List<Notice>> watch(UserProfile user) => _db
      .collection('users/${user.uid}/notifications')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            Notice(
              id: doc.id,
              kind: NoticeKind.fromCode(doc.data()['kind'] as String?),
              title: doc.data()['title'] as String? ?? '',
              body: doc.data()['body'] as String? ?? '',
              workOrderId: doc.data()['workOrderRef'] as String?,
              createdAt:
                  (doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              read: doc.data()['readAt'] != null,
            ),
        ],
      );

  @override
  Future<void> markRead(UserProfile user, Notice notice) => _db
      .doc('users/${user.uid}/notifications/${notice.id}')
      .update({'readAt': FieldValue.serverTimestamp()});
}
