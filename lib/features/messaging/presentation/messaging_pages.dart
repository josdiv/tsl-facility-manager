import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_frames.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../work_orders/domain/work_order.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';
import '../domain/chat.dart';

/// Which orders a role may hold a conversation about.
List<WorkOrder> ordersForRole(
  WorkOrdersState state,
  AppRole role,
  String uid,
) => switch (role) {
  AppRole.client => state.submittedBy(uid),
  AppRole.staff => state.assignedTo(uid),
  AppRole.supervisor => state.orders,
};

/// Short time for chat: "14:05" today, otherwise the date too.
String chatTimeLabel(DateTime value, DateTime now) {
  final sameDay = DateUtils.isSameDay(value, now);
  final time =
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  return sameDay ? time : dateTimeLabel(value, now);
}

/// Each role's list of work order conversations, newest first.
class ConversationsPage extends StatelessWidget {
  const ConversationsPage({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final orders =
        ordersForRole(
            context.watch<WorkOrdersBloc>().state,
            role,
            context.profileOf(role).uid,
          ).where((order) => order.lastMessageAt != null).toList()
          ..sort((a, b) => b.lastMessageAt!.compareTo(a.lastMessageAt!));
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final items = <Widget>[
      if (orders.isEmpty) const EmptyListMessage('No conversations yet.'),
      for (final order in orders)
        AppCard(
          onTap: () => context.push(AppRoutes.chat(role, order.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(order.title, style: text.titleMedium)),
                  Text(
                    chatTimeLabel(order.lastMessageAt!, now),
                    style: text.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(order.id, style: text.bodySmall),
              const SizedBox(height: 8),
              Text(
                order.lastMessagePreview ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
    ];
    return role == AppRole.client
        ? TabPage(title: 'Messages', role: role, children: items)
        : DetailPage(title: 'Messages', children: items);
  }
}

class ChatPage extends StatelessWidget {
  const ChatPage({required this.role, required this.id, super.key});

  final AppRole role;
  final String id;

  @override
  Widget build(BuildContext context) {
    return WorkOrderScope(
      id: id,
      builder: (context, order) => ChatThread(
        role: role,
        chat: WorkOrderChat(order.id),
        title: 'Messages',
        banner: '${order.id} · ${order.title}',
      ),
    );
  }
}

/// One support conversation per user.
class SupportChatPage extends StatelessWidget {
  const SupportChatPage({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return ChatThread(
      role: role,
      chat: SupportChat(context.profileOf(role).uid),
      title: 'Message support',
      banner: 'TSL support · We reply during working hours',
      emptyMessage:
          'Ask a question or report a problem with the app. Our support team '
          'replies here.',
    );
  }
}

class ChatThread extends StatefulWidget {
  const ChatThread({
    required this.role,
    required this.chat,
    required this.title,
    required this.banner,
    this.emptyMessage = 'No messages yet. Send the first one below.',
    super.key,
  });

  final AppRole role;
  final ChatRef chat;
  final String title;
  final String banner;
  final String emptyMessage;

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _draft = TextEditingController();
  late Stream<List<ChatMessage>> _messages = _watch();

  Stream<List<ChatMessage>> _watch() =>
      context.read<ChatRepository>().watch(widget.chat);

  @override
  void didUpdateWidget(ChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat != widget.chat) _messages = _watch();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send(UserProfile me) async {
    final message = _draft.text.trim();
    if (message.isEmpty) return;
    _draft.clear();
    try {
      await context.read<ChatRepository>().send(widget.chat, message, me);
    } on ChatFailure catch (failure) {
      if (!mounted) return;
      _draft.text = message; // Give the text back to try again.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.profileOf(widget.role);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primarySoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                widget.banner,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messages,
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? const <ChatMessage>[];
                  if (messages.isEmpty) {
                    return EmptyListMessage(widget.emptyMessage);
                  }
                  final now = DateTime.now();
                  // Newest at the bottom, and the list starts there.
                  return ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final message in messages.reversed)
                        _Bubble(
                          message,
                          mine: message.senderId == me.uid,
                          now: now,
                        ),
                    ],
                  );
                },
              ),
            ),
            ColoredBox(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _draft,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type a message…',
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Send message',
                      onPressed: () => _send(me),
                      icon: const Icon(Icons.send, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message, {required this.mine, required this.now});

  final ChatMessage message;
  final bool mine;
  final DateTime now;

  /// "Sarah · Facility team" for supervisors and admins, otherwise the first
  /// name.
  String get _sender {
    final first = message.senderName.trim().split(RegExp(r'\s+')).first;
    return switch (message.senderRole) {
      'supervisor' || 'admin' => '$first · Facility team',
      _ => first,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.surface,
          border: mine ? null : Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: mine ? Colors.white : AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${mine ? 'You' : _sender} · '
              '${chatTimeLabel(message.sentAt, now)}',
              style: TextStyle(
                fontSize: 12,
                color: mine ? const Color(0xFFF7E8F2) : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
