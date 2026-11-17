import 'dart:async';

import '../../profile/domain/user_profile.dart';
import '../../work_orders/data/in_memory_work_order_repository.dart';
import '../domain/chat.dart';

/// Sample conversations for tests and SAMPLE_DATA builds.
class InMemoryChatRepository implements ChatRepository {
  InMemoryChatRepository({
    InMemoryWorkOrderRepository? workOrders,
    DateTime? now,
  }) : _workOrders = workOrders {
    final at = now ?? DateTime.now();
    DateTime minutesAgo(int minutes) => at.subtract(Duration(minutes: minutes));
    _seed(const WorkOrderChat('WO-1048'), [
      ChatMessage(
        text: 'Hello Daniel, Emeka is on his way to inspect the unit.',
        senderId: 'sarah',
        senderName: 'Sarah James',
        senderRole: 'supervisor',
        sentAt: minutesAgo(216),
      ),
      ChatMessage(
        text: 'Thank you. The east wing is accessible.',
        senderId: 'daniel',
        senderName: 'Daniel Clarke',
        senderRole: 'client',
        sentAt: minutesAgo(210),
      ),
      ChatMessage(
        text:
            'We have identified low refrigerant pressure. We’ll update you '
            'shortly.',
        senderId: 'emeka',
        senderName: 'Emeka Okafor',
        senderRole: 'staff',
        sentAt: minutesAgo(168),
      ),
    ]);
    _seed(const WorkOrderChat('WO-1039'), [
      ChatMessage(
        text: 'Tunde will look at the washroom tap tomorrow morning.',
        senderId: 'sarah',
        senderName: 'Sarah James',
        senderRole: 'supervisor',
        sentAt: minutesAgo(60),
      ),
    ]);
  }

  final InMemoryWorkOrderRepository? _workOrders;
  final _threads = <ChatRef, List<ChatMessage>>{};
  final _changes = StreamController<ChatRef>.broadcast();

  void _seed(ChatRef chat, List<ChatMessage> messages) {
    _threads[chat] = messages;
    _record(chat, messages.last);
  }

  void _record(ChatRef chat, ChatMessage message) {
    if (chat is WorkOrderChat) {
      _workOrders?.recordMessage(
        chat.workOrderId,
        message.text,
        message.sentAt,
      );
    }
  }

  @override
  Stream<List<ChatMessage>> watch(ChatRef chat) async* {
    yield List.unmodifiable(_threads[chat] ?? const <ChatMessage>[]);
    yield* _changes.stream
        .where((changed) => changed == chat)
        .map((_) => List.unmodifiable(_threads[chat]!));
  }

  @override
  Future<void> send(ChatRef chat, String text, UserProfile sender) async {
    final message = ChatMessage(
      text: text,
      senderId: sender.uid,
      senderName: sender.name,
      senderRole: sender.role.path,
      sentAt: DateTime.now(),
    );
    _threads[chat] = [...?_threads[chat], message];
    _record(chat, message);
    _changes.add(chat);
  }
}
