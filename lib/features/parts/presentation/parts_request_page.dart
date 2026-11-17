import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/labelled_field.dart';
import '../../../core/widgets/page_frames.dart';
import '../../work_orders/data/sample_work_orders.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';
import '../domain/requisition.dart';
import 'requisitions_cubit.dart';

/// Checks a requested quantity against what the location has in stock.
String? quantityError(String? value, int stock) {
  final quantity = int.tryParse(value?.trim() ?? '');
  if (quantity == null || quantity < 1) return 'Enter a quantity of at least 1';
  if (quantity > stock) return 'Only $stock in stock at this location';
  return null;
}

BadgeTone _toneFor(RequisitionStatus status) => switch (status) {
  RequisitionStatus.pending => BadgeTone.warning,
  RequisitionStatus.approved => BadgeTone.success,
  RequisitionStatus.rejected => BadgeTone.danger,
};

/// The Parts tab: the technician's requests and their approval status.
class PartsListPage extends StatelessWidget {
  const PartsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final requests = context.watch<RequisitionsCubit>().state;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    return TabPage(
      title: 'Parts',
      role: AppRole.staff,
      children: [
        Text('Parts requests', style: text.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Stock is issued after facility admin approval.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.push(AppRoutes.staffPartsNew()),
          icon: const Icon(Icons.add),
          label: const Text('Request parts'),
        ),
        const SizedBox(height: 16),
        if (requests.isEmpty)
          const EmptyListMessage('You haven’t requested any parts yet.'),
        for (final request in requests)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [request.ref, ?request.workOrderId].join(' · '),
                        style: text.bodySmall,
                      ),
                    ),
                    Text(
                      dateTimeLabel(request.requestedAt, now),
                      style: text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppBadge(request.status.label, tone: _toneFor(request.status)),
                const SizedBox(height: 8),
                Text(
                  '${request.quantity} × ${request.itemName}',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(request.reason, style: text.bodyMedium),
                if (request.rejectionReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Admin: ${request.rejectionReason}',
                    style: text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The request form. Opened from the Parts tab, or from a task with that
/// work order already chosen.
class PartsRequestPage extends StatefulWidget {
  const PartsRequestPage({this.workOrderId, super.key});

  final String? workOrderId;

  @override
  State<PartsRequestPage> createState() => _PartsRequestPageState();
}

class _PartsRequestPageState extends State<PartsRequestPage> {
  static const _items = {
    'HVAC air filter': 24,
    'LED panel': 8,
    'Generator oil': 6,
  };
  static const _noOrder = 'None · general stock';

  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  var _item = _items.keys.first;
  late String? _workOrderId = widget.workOrderId;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final ref = context.read<RequisitionsCubit>().submit(
      itemName: _item,
      quantity: int.parse(_quantity.text.trim()),
      reason: _reason.text.trim(),
      workOrderId: _workOrderId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$ref submitted for admin approval')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.staffParts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final orders = context
        .watch<WorkOrdersBloc>()
        .state
        .assignedTo(sampleStaff)
        .where((order) => order.status.isActive)
        .toList();
    String labelFor(String id) {
      final order = orders.where((o) => o.id == id).firstOrNull;
      return order == null ? id : '${order.id} · ${order.title}';
    }

    final stock = _items[_item]!;
    return DetailPage(
      title: 'Request parts',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Stock is issued after facility admin approval.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              LabelledDropdown(
                label: 'Linked work order',
                options: [_noOrder, for (final o in orders) labelFor(o.id)],
                initialValue: _workOrderId == null
                    ? _noOrder
                    : labelFor(_workOrderId!),
                onChanged: (value) => _workOrderId = value == _noOrder
                    ? null
                    : value.split(' · ').first,
              ),
              const LabelledDropdown(
                label: 'Location',
                options: ['Marina Towers, Lagos'],
              ),
              LabelledDropdown(
                label: 'Inventory item',
                options: [
                  for (final item in _items.entries)
                    '${item.key} · ${item.value} in stock',
                ],
                onChanged: (value) =>
                    setState(() => _item = value.split(' · ').first),
              ),
              LabelledTextField(
                label: 'Quantity',
                hint: 'e.g. 2',
                controller: _quantity,
                keyboardType: TextInputType.number,
                validator: (value) => quantityError(value, stock),
              ),
              LabelledTextField(
                label: 'Reason',
                hint: 'Why are these parts needed?',
                controller: _reason,
                maxLines: 3,
                validator: (value) =>
                    requiredText(value, 'Say why these parts are needed'),
              ),
              InfoBanner(
                'Available stock: $stock units. Approval will deduct the '
                'requested quantity from this location’s inventory.',
                icon: Icons.inventory_2_outlined,
                tone: BannerTone.neutral,
              ),
              FilledButton(
                onPressed: _submit,
                child: const Text('Submit requisition'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
