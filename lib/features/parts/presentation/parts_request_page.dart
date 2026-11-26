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
import '../../profile/presentation/profile_cubit.dart';
import '../../work_orders/data/sample_work_orders.dart';
import '../../work_orders/presentation/bloc/work_orders_bloc.dart';
import '../../work_orders/presentation/widgets/work_order_scope.dart';
import '../../work_orders/domain/work_order.dart';
import '../domain/requisition.dart';

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

/// The Parts tab: the technician's or supervisor's requests and their
/// approval status.
class PartsListPage extends StatefulWidget {
  const PartsListPage({this.role = AppRole.staff, super.key});

  final AppRole role;

  @override
  State<PartsListPage> createState() => _PartsListPageState();
}

class _PartsListPageState extends State<PartsListPage> {
  String? _uid;
  Stream<List<Requisition>> _requests = const Stream.empty();

  @override
  Widget build(BuildContext context) {
    final me = context.profileOf(widget.role);
    if (me.uid != _uid) {
      _uid = me.uid;
      _requests = context.read<PartsRepository>().watchRequests(me);
    }
    return StreamBuilder<List<Requisition>>(
      stream: _requests,
      builder: (context, snapshot) => _list(context, snapshot.data ?? const []),
    );
  }

  Widget _list(BuildContext context, List<Requisition> requests) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    return TabPage(
      title: 'Parts',
      role: widget.role,
      children: [
        Text('Parts requests', style: text.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Stock is issued after facility admin approval.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.push(AppRoutes.partsNew(widget.role)),
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
                        [
                          if (request.ref.isEmpty)
                            'New request'
                          else
                            request.ref,
                          ?request.workOrderId,
                        ].join(' · '),
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
  const PartsRequestPage({
    this.role = AppRole.staff,
    this.workOrderId,
    super.key,
  });

  /// Staff or a supervisor, each for their own facility.
  final AppRole role;
  final String? workOrderId;

  @override
  State<PartsRequestPage> createState() => _PartsRequestPageState();
}

class _PartsRequestPageState extends State<PartsRequestPage> {
  static const _noOrder = 'None · general stock';

  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  late final Stream<List<StockItem>> _stock = context
      .read<PartsRepository>()
      .watchStock(
        context.read<ProfileCubit>().of(widget.role).locationId ?? '',
      );
  String? _itemId;
  late String? _workOrderId = widget.workOrderId;
  var _sending = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(StockItem? item) async {
    if (_sending || item == null || !_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _sending = true);
    try {
      await context.read<PartsRepository>().request(
        context.read<ProfileCubit>().of(widget.role),
        item: item,
        quantity: int.parse(_quantity.text.trim()),
        reason: _reason.text.trim(),
        workOrderId: _workOrderId,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Request submitted for admin approval')),
      );
      router.canPop() ? router.pop() : router.go(AppRoutes.parts(widget.role));
    } on PartsFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Staff link their own tasks; supervisors any open job at their facility.
    final state = context.watch<WorkOrdersBloc>().state;
    final orders =
        (widget.role == AppRole.staff
                ? state.assignedTo(context.profileOf(AppRole.staff).uid)
                : state.orders)
            .where((order) => order.status.isActive)
            .toList();
    String labelFor(String id) {
      final order = orders.where((o) => o.id == id).firstOrNull;
      return order == null ? id : '${order.id} · ${order.title}';
    }

    return StreamBuilder<List<StockItem>>(
      stream: _stock,
      builder: (context, snapshot) =>
          _buildForm(context, orders, labelFor, snapshot.data ?? const []),
    );
  }

  Widget _buildForm(
    BuildContext context,
    List<WorkOrder> orders,
    String Function(String) labelFor,
    List<StockItem> items,
  ) {
    final text = Theme.of(context).textTheme;
    final item =
        items.where((i) => i.id == _itemId).firstOrNull ?? items.firstOrNull;
    final stock = item?.quantity ?? 0;
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
              LabelledDropdown(
                label: 'Location',
                options: [context.profileOf(widget.role).facility],
              ),
              if (items.isEmpty)
                const InfoBanner(
                  'No stock is recorded at your facility yet.',
                  icon: Icons.inventory_2_outlined,
                  tone: BannerTone.warning,
                )
              else
                LabelledDropdown(
                  label: 'Inventory item',
                  options: [
                    for (final i in items) '${i.name} · ${i.quantity} in stock',
                  ],
                  onChanged: (value) => setState(
                    () => _itemId = items
                        .firstWhere(
                          (i) => '${i.name} · ${i.quantity} in stock' == value,
                        )
                        .id,
                  ),
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
                onPressed: _sending || item == null
                    ? null
                    : () => _submit(item),
                child: const Text('Submit requisition'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
