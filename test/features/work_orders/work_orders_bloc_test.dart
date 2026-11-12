import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/work_orders/data/in_memory_work_order_repository.dart';
import 'package:tsl_facility_manager/features/work_orders/data/sample_work_orders.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order.dart';
import 'package:tsl_facility_manager/features/work_orders/presentation/bloc/work_orders_bloc.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10);

  WorkOrdersBloc build() =>
      WorkOrdersBloc(InMemoryWorkOrderRepository(now: now), clock: () => now);

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'loads the sample orders',
    build: build,
    act: (bloc) => bloc.add(const WorkOrdersRequested()),
    verify: (bloc) {
      expect(bloc.state.orders, hasLength(8));
      expect(bloc.state.byId('WO-1048')?.status, WorkOrderStatus.inProgress);
      expect(bloc.state.byId('missing'), isNull);
    },
  );

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'filters by client, assignee and review queue',
    build: build,
    act: (bloc) => bloc.add(const WorkOrdersRequested()),
    verify: (bloc) {
      final state = bloc.state;
      expect(
        state.submittedBy(sampleClient).map((o) => o.id),
        containsAll(['WO-1048', 'WO-1040', 'WO-1039', 'WO-1037']),
      );
      expect(
        state.assignedTo(sampleStaff).every((o) => o.assignee == sampleStaff),
        isTrue,
      );
      expect(state.awaitingReview.map((o) => o.id), ['WO-1043', 'WO-1037']);
      expect(state.teamActive.any((o) => o.isAwaitingReview), isFalse);
      expect(
        state.teamActive.any((o) => o.status == WorkOrderStatus.completed),
        isFalse,
      );
    },
  );

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'applies a lifecycle change using the bloc clock',
    build: build,
    act: (bloc) async {
      bloc.add(const WorkOrdersRequested());
      await bloc.stream.first;
      bloc.add(WorkOrderChanged('WO-1047', (order, at) => order.start(at)));
    },
    wait: Duration.zero,
    verify: (bloc) {
      final order = bloc.state.byId('WO-1047')!;
      expect(order.status, WorkOrderStatus.inProgress);
      expect(order.history.last.at, now);
    },
  );

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'a report creates a new open client order with the next reference',
    build: build,
    act: (bloc) async {
      bloc.add(const WorkOrdersRequested());
      await bloc.stream.first;
      bloc.add(
        const IssueReported(
          title: 'Broken window',
          description: 'Reception window is cracked',
          location: 'Marina Towers, Lagos',
          zone: 'Reception',
          media: ['Photo-1.jpg'],
          submittedBy: sampleClient,
        ),
      );
    },
    wait: Duration.zero,
    verify: (bloc) {
      expect(bloc.state.lastReportedId, 'WO-1049');
      final order = bloc.state.orders.first;
      expect(order.id, 'WO-1049');
      expect(order.status, WorkOrderStatus.open);
      expect(order.type, WorkOrderType.client);
      expect(order.reportMedia, ['Photo-1.jpg']);
      expect(order.assignee, isNull);
    },
  );

  test('repository replaces an order with the same id', () async {
    final repository = InMemoryWorkOrderRepository(now: now);
    final original = (await repository.getAll()).first;
    await repository.save(original.reassign(assignee: 'Tunde', at: now));
    final all = await repository.getAll();
    expect(all, hasLength(8));
    expect(all.first.assignee, 'Tunde');
  });
}
