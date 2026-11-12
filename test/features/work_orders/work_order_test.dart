import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10);

  WorkOrder order(WorkOrderStatus status, {DateTime? due}) => WorkOrder(
    id: 'WO-1',
    title: 'Title',
    description: 'Description',
    type: WorkOrderType.client,
    status: status,
    location: 'Marina Towers, Lagos',
    zone: 'Reception',
    due: due ?? now.add(const Duration(hours: 1)),
    submittedBy: 'Client',
    assignee: 'Emeka',
  );

  WorkOrder submit(WorkOrder o) =>
      o.submit(note: 'Done', media: const ['a.jpg'], at: now);

  group('lifecycle', () {
    test('start moves Open to In Progress and records it', () {
      final started = order(WorkOrderStatus.open).start(now);
      expect(started.status, WorkOrderStatus.inProgress);
      expect(started.history.last.title, 'Technician working on it');
    });

    test('submit moves to Pending Review and locks editing', () {
      final submitted = submit(order(WorkOrderStatus.inProgress));
      expect(submitted.status, WorkOrderStatus.pendingReview);
      expect(submitted.isEditableByStaff, isFalse);
      expect(submitted.submittedAt, now);
      expect(submitted.workMedia, ['a.jpg']);
    });

    test('confirm completes reviewed work', () {
      final done = order(WorkOrderStatus.pendingReview).confirm(at: now);
      expect(done.status, WorkOrderStatus.completed);
    });

    test('return unlocks editing and keeps the feedback', () {
      final returned = order(WorkOrderStatus.pendingReview).returnForCorrection(
        reason: 'Safety concern',
        feedback: 'Secure the cable',
        media: const ['b.jpg'],
        assignee: 'Tunde',
        at: now,
      );
      expect(returned.status, WorkOrderStatus.returned);
      expect(returned.isEditableByStaff, isTrue);
      expect(returned.returnFeedback, 'Secure the cable');
      expect(returned.assignee, 'Tunde');
    });

    test('returned work can be resubmitted', () {
      final returned = order(WorkOrderStatus.pendingReview).returnForCorrection(
        reason: 'r',
        feedback: 'f',
        media: const [],
        assignee: 'Emeka',
        at: now,
      );
      expect(submit(returned).status, WorkOrderStatus.pendingReview);
    });

    test('reassign changes the assignee and records it', () {
      final moved = order(WorkOrderStatus.open)
          .reassign(assignee: 'Tunde', at: now);
      expect(moved.assignee, 'Tunde');
      expect(moved.history.last.title, 'Assigned to Tunde');
    });
  });

  group('illegal transitions are refused', () {
    test('cannot start work that has already started', () {
      expect(
        () => order(WorkOrderStatus.inProgress).start(now),
        throwsStateError,
      );
    });

    test('cannot submit locked or unstarted work', () {
      for (final status in [
        WorkOrderStatus.open,
        WorkOrderStatus.pendingReview,
        WorkOrderStatus.completed,
      ]) {
        expect(() => submit(order(status)), throwsStateError);
      }
    });

    test('cannot confirm or return work that is not under review', () {
      final inProgress = order(WorkOrderStatus.inProgress);
      expect(() => inProgress.confirm(at: now), throwsStateError);
      expect(
        () => inProgress.returnForCorrection(
          reason: 'r',
          feedback: 'f',
          media: const [],
          assignee: 'a',
          at: now,
        ),
        throwsStateError,
      );
    });

    test('cannot reassign completed work', () {
      expect(
        () => order(WorkOrderStatus.completed).reassign(assignee: 'a', at: now),
        throwsStateError,
      );
    });
  });

  group('overdue flag', () {
    final past = now.subtract(const Duration(hours: 1));

    test('applies to active work past its due date', () {
      expect(order(WorkOrderStatus.open, due: past).isOverdueAt(now), isTrue);
      expect(
        order(WorkOrderStatus.returned, due: past).isOverdueAt(now),
        isTrue,
      );
    });

    test('does not apply before the due date', () {
      expect(order(WorkOrderStatus.open).isOverdueAt(now), isFalse);
    });

    test('does not apply to submitted or completed work', () {
      expect(
        order(WorkOrderStatus.pendingReview, due: past).isOverdueAt(now),
        isFalse,
      );
      expect(
        order(WorkOrderStatus.completed, due: past).isOverdueAt(now),
        isFalse,
      );
    });
  });

  test('clients see returned work as In Progress', () {
    expect(WorkOrderStatus.returned.clientLabel, 'In Progress');
    expect(WorkOrderStatus.pendingReview.clientLabel, 'Pending Review');
  });
}
