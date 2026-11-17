import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/profile/domain/user_profile.dart';
import 'package:tsl_facility_manager/core/session/app_role.dart';
import 'package:tsl_facility_manager/features/work_orders/data/in_memory_work_order_repository.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order_repository.dart';
import 'package:tsl_facility_manager/features/work_orders/presentation/bloc/work_orders_bloc.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10);
  final client = sampleProfiles[AppRole.client]!;

  WorkOrdersBloc build() =>
      WorkOrdersBloc(InMemoryWorkOrderRepository(now: now), clock: () => now);

  Future<void> load(WorkOrdersBloc bloc) async {
    bloc.add(const WorkOrdersRequested());
    await bloc.stream.firstWhere((s) => s.orders.isNotEmpty);
  }

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'loads the sample orders',
    build: build,
    act: load,
    verify: (bloc) {
      expect(bloc.state.orders, hasLength(8));
      expect(bloc.state.byId('WO-1048')?.status, WorkOrderStatus.inProgress);
      expect(bloc.state.byId('missing'), isNull);
    },
  );

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'filters by client account, assignee account and review queue',
    build: build,
    act: load,
    verify: (bloc) {
      final state = bloc.state;
      expect(
        state.submittedBy('daniel').map((o) => o.id),
        containsAll(['WO-1048', 'WO-1040', 'WO-1039', 'WO-1037']),
      );
      expect(
        state.assignedTo('emeka').every((o) => o.assignee == 'Emeka Okafor'),
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
      await load(bloc);
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
    'an impossible change is reported, not thrown',
    build: build,
    act: (bloc) async {
      await load(bloc);
      // WO-1048 is already in progress, so it can't be started again.
      bloc.add(WorkOrderChanged('WO-1048', (order, at) => order.start(at)));
    },
    wait: Duration.zero,
    verify: (bloc) {
      expect(bloc.state.failureCount, 1);
      expect(bloc.state.failure!.message, contains('WO-1048'));
      expect(bloc.state.byId('WO-1048')!.status, WorkOrderStatus.inProgress);
    },
  );

  blocTest<WorkOrdersBloc, WorkOrdersState>(
    'a report creates a new open client order with the next reference',
    build: build,
    act: (bloc) async {
      await load(bloc);
      bloc.add(
        IssueReported(
          const IssueDraft(
            title: 'Broken window',
            description: 'Reception window is cracked',
            location: Facility('marina', 'Marina Towers, Lagos'),
            zone: Zone('marina-reception', 'Reception'),
            media: ['Photo-1.jpg'],
          ),
          client,
        ),
      );
    },
    wait: Duration.zero,
    verify: (bloc) {
      expect(bloc.state.lastReportedId, 'WO-1049');
      final order = bloc.state.byId('WO-1049')!;
      expect(order.status, WorkOrderStatus.open);
      expect(order.type, WorkOrderType.client);
      expect(order.reportMedia, ['Photo-1.jpg']);
      expect(order.submittedById, 'daniel');
      expect(order.zoneId, 'marina-reception');
      expect(order.assignee, isNull);
    },
  );

  test('the repository updates an order in place', () async {
    final repository = InMemoryWorkOrderRepository(now: now);
    final original = (await repository.watch(null).first).first;
    await repository.update(
      original,
      original.reassign(assignee: 'Tunde Bakare', assigneeId: 'tunde', at: now),
    );
    final all = await repository.watch(null).first;
    expect(all, hasLength(8));
    expect(all.first.assigneeId, 'tunde');
  });
}
