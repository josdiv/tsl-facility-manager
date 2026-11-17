import 'package:equatable/equatable.dart';

import '../../profile/domain/user_profile.dart';

/// Which conversation: the chat on a work order, or a user's support chat.
sealed class ChatRef extends Equatable {
  const ChatRef();
}

class WorkOrderChat extends ChatRef {
  const WorkOrderChat(this.workOrderId);

  /// The work order's reference, such as `WO-1048`.
  final String workOrderId;

  @override
  List<Object?> get props => [workOrderId];
}

class SupportChat extends ChatRef {
  const SupportChat(this.uid);

  /// The account the support conversation belongs to.
  final String uid;

  @override
  List<Object?> get props => [uid];
}

/// One message. Matches `.../messages/{id}` in docs/firestore-schema.md.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.sentAt,
  });

  final String text;
  final String senderId;
  final String senderName;

  /// `admin`, `supervisor`, `staff` or `client`.
  final String senderRole;
  final DateTime sentAt;

  @override
  List<Object?> get props => [text, senderId, senderName, senderRole, sentAt];
}

/// Why a message couldn't be sent, in words the app can show.
class ChatFailure implements Exception {
  const ChatFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ChatRepository {
  /// The conversation's messages, oldest first, kept up to date.
  Stream<List<ChatMessage>> watch(ChatRef chat);

  /// Sends [text] as [sender]. Throws [ChatFailure] if it can't be sent.
  Future<void> send(ChatRef chat, String text, UserProfile sender);
}
