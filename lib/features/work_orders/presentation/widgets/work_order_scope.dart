import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/page_frames.dart';
import '../../domain/work_order.dart';
import '../../domain/work_order_repository.dart';
import '../bloc/work_orders_bloc.dart';

/// Rebuilds [builder] when the order or its timeline changes, shows a clear
/// message for a reference that doesn't exist, and reports changes that
/// couldn't be saved.
class WorkOrderScope extends StatefulWidget {
  const WorkOrderScope({required this.id, required this.builder, super.key});

  final String id;
  final Widget Function(BuildContext context, WorkOrder order) builder;

  @override
  State<WorkOrderScope> createState() => _WorkOrderScopeState();
}

class _WorkOrderScopeState extends State<WorkOrderScope> {
  String? _historyFor;
  Stream<List<WorkOrderEvent>> _history = const Stream.empty();

  @override
  Widget build(BuildContext context) {
    final order = context.select<WorkOrdersBloc, WorkOrder?>(
      (bloc) => bloc.state.byId(widget.id),
    );
    if (order == null) {
      return const DetailPage(
        title: 'Work order',
        children: [
          Text(
            'This work order could not be found.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    if (_historyFor != order.id) {
      _historyFor = order.id;
      _history = context.read<WorkOrderRepository>().watchHistory(order.id);
    }
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listenWhen: (before, after) =>
          after.failureCount != before.failureCount &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      listener: (context, state) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.failure!.message))),
      child: StreamBuilder<List<WorkOrderEvent>>(
        stream: _history,
        builder: (context, snapshot) => widget.builder(
          context,
          snapshot.hasData ? order.withHistory(snapshot.data!) : order,
        ),
      ),
    );
  }
}

/// Simple empty state for a list with nothing in it.
class EmptyListMessage extends StatelessWidget {
  const EmptyListMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
