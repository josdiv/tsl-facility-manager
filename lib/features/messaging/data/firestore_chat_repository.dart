import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/chat.dart';

/// Chats in Firestore: `workOrders/{id}/messages` and
/// `supportThreads/{uid}/messages`. The previews on work orders and support
/// threads are kept by Cloud Functions.
class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository({
    required String? Function(String ref) workOrderDocId,
    FirebaseFirestore? firestore,
  }) : _docIdFor = workOrderDocId,
       _db = firestore ?? appFirestore();

  final String? Function(String ref) _docIdFor;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>>? _messages(ChatRef chat) =>
      switch (chat) {
        WorkOrderChat(:final workOrderId) => switch (_docIdFor(workOrderId)) {
          final docId? => _db.collection('workOrders/$docId/messages'),
          null => null,
        },
        SupportChat(:final uid) => _db.collection(
          'supportThreads/$uid/messages',
        ),
      };

  @override
  Stream<List<ChatMessage>> watch(ChatRef chat) {
    final messages = _messages(chat);
    if (messages == null) return Stream.value(const []);
    return messages
        .orderBy('sentAt')
        .snapshots()
        .map(
          (snap) => [for (final doc in snap.docs) messageFromDoc(doc.data())],
        );
  }

  @override
  Future<void> send(ChatRef chat, String text, UserProfile sender) async {
    final messages = _messages(chat);
    if (messages == null) {
      throw const ChatFailure('This conversation isn’t available yet.');
    }
    try {
      // Offline, Firestore keeps the message and sends it later, so don't
      // wait for the server here.
      messages.add({
        'text': text,
        'senderId': sender.uid,
        'senderName': sender.name,
        'senderRole': sender.role.path,
        'sentAt': FieldValue.serverTimestamp(),
      }).ignore();
    } on FirebaseException {
      throw const ChatFailure('Your message couldn’t be sent. Try again.');
    }
  }
}

/// A message from its document. A message still waiting for the server has
/// no timestamp yet, so it shows as sent now.
ChatMessage messageFromDoc(Map<String, dynamic> d) => ChatMessage(
  text: d['text'] as String? ?? '',
  senderId: d['senderId'] as String? ?? '',
  senderName: d['senderName'] as String? ?? '',
  senderRole: d['senderRole'] as String? ?? '',
  sentAt: (d['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
);
