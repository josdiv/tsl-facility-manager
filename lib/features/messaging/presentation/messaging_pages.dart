import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_frames.dart';
import '../../work_orders/data/sample_work_orders.dart';
import '../../work_orders/domain/work_order.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';

class ChatMessage extends Equatable {
  const ChatMessage(this.sender, this.senderLabel, this.text, this.time);

  final AppRole sender;
  final String senderLabel;
  final String text;
  final String time;

  @override
  List<Object?> get props => [sender, senderLabel, text, time];
}

/// Conversations keyed by work order id. Sample data until Firebase arrives.
class MessagesCubit extends Cubit<Map<String, List<ChatMessage>>> {
  MessagesCubit() : super(_sample);

  static const _sample = {
    'WO-1048': [
      ChatMessage(
        AppRole.supervisor,
        'Sarah · Facility team',
        'Hello Daniel, Emeka is on his way to inspect the unit.',
        '08:24',
      ),
      ChatMessage(
        AppRole.client,
        'Daniel',
        'Thank you. The east wing is accessible.',
        '08:28',
      ),
      ChatMessage(
        AppRole.staff,
        'Emeka',
        'We have identified low refrigerant pressure. We’ll update you shortly.',
        '09:10',
      ),
    ],
    'WO-1039': [
      ChatMessage(
        AppRole.supervisor,
        'Sarah · Facility team',
        'Tunde will look at the washroom tap tomorrow morning.',
        '11:02',
      ),
    ],
  };

  void send(String id, ChatMessage message) => emit({
    ...state,
    id: [...?state[id], message],
  });
}

/// Which orders a role may hold a conversation about.
List<WorkOrder> ordersForRole(WorkOrdersState state, AppRole role) =>
    switch (role) {
      AppRole.client => state.submittedBy(sampleClient),
      AppRole.staff => state.assignedTo(sampleStaff),
      AppRole.supervisor => state.orders,
    };

/// Gap in the design: chats belong to a work order, so each role needs a list.
class ConversationsPage extends StatelessWidget {
  const ConversationsPage({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final threads = context.watch<MessagesCubit>().state;
    final orders = ordersForRole(
      context.watch<WorkOrdersBloc>().state,
      role,
    ).where((order) => threads[order.id]?.isNotEmpty ?? false).toList();
    final text = Theme.of(context).textTheme;
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
                  Text(threads[order.id]!.last.time, style: text.bodySmall),
                ],
              ),
              const SizedBox(height: 2),
              Text(order.id, style: text.bodySmall),
              const SizedBox(height: 8),
              Text(
                threads[order.id]!.last.text,
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

class ChatPage extends StatefulWidget {
  const ChatPage({required this.role, required this.id, super.key});

  final AppRole role;
  final String id;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _send() {
    final message = _draft.text.trim();
    if (message.isEmpty) return;
    final now = TimeOfDay.now();
    context.read<MessagesCubit>().send(
      widget.id,
      ChatMessage(
        widget.role,
        widget.role.label,
        message,
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}',
      ),
    );
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = context.select<MessagesCubit, List<ChatMessage>>(
      (cubit) => cubit.state[widget.id] ?? const [],
    );
    return WorkOrderScope(
      id: widget.id,
      builder: (context, order) => Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.primarySoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  '${order.id} · ${order.title}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const EmptyListMessage(
                        'No messages yet. Send the first one below.',
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final message in messages)
                            _Bubble(
                              message,
                              mine: message.sender == widget.role,
                            ),
                        ],
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
                          decoration: const InputDecoration(
                            hintText: 'Type a follow-up message…',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send message',
                        onPressed: _send,
                        icon: const Icon(Icons.send, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message, {required this.mine});

  final ChatMessage message;
  final bool mine;

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
              '${mine ? 'You' : message.senderLabel} · ${message.time}',
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
