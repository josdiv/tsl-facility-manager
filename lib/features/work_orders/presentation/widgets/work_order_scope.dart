import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/page_frames.dart';
import '../../domain/work_order.dart';
import '../bloc/work_orders_bloc.dart';

/// Rebuilds [builder] when the order changes, and shows a clear message for a
/// reference that doesn't exist.
class WorkOrderScope extends StatelessWidget {
  const WorkOrderScope({required this.id, required this.builder, super.key});

  final String id;
  final Widget Function(BuildContext context, WorkOrder order) builder;

  @override
  Widget build(BuildContext context) {
    final order = context.select<WorkOrdersBloc, WorkOrder?>(
      (bloc) => bloc.state.byId(id),
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
    return builder(context, order);
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
