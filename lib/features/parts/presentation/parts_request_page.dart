import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/labelled_field.dart';
import '../../../core/widgets/page_frames.dart';
import '../../work_orders/data/sample_work_orders.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';

/// Checks a requested quantity against what the location has in stock.
String? quantityError(String? value, int stock) {
  final quantity = int.tryParse(value?.trim() ?? '');
  if (quantity == null || quantity < 1) return 'Enter a quantity of at least 1';
  if (quantity > stock) return 'Only $stock in stock at this location';
  return null;
}

class PartsRequestPage extends StatefulWidget {
  const PartsRequestPage({super.key});

  @override
  State<PartsRequestPage> createState() => _PartsRequestPageState();
}

class _PartsRequestPageState extends State<PartsRequestPage> {
  static const _items = {
    'HVAC air filter': 24,
    'LED panel': 8,
    'Generator oil': 6,
  };

  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  var _item = _items.keys.first;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('REQ-082 submitted for admin approval')),
    );
    _quantity.clear();
    _reason.clear();
    context.go(AppRoutes.staffTasks);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final orders = context
        .watch<WorkOrdersBloc>()
        .state
        .assignedTo(sampleStaff)
        .where((order) => order.status.isActive)
        .map((order) => '${order.id} · ${order.title}')
        .toList();
    final stock = _items[_item]!;
    return TabPage(
      title: 'Parts request',
      role: AppRole.staff,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Request parts', style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Stock is issued after facility admin approval.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (orders.isNotEmpty)
                LabelledDropdown(
                  key: ValueKey(orders.length),
                  label: 'Linked work order',
                  options: orders,
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
