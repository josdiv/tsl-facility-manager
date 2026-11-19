import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/work_orders/data/firestore_work_order_repository.dart';
import 'package:tsl_facility_manager/features/work_orders/data/sample_work_orders.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order.dart';

/// The Firestore writes must touch exactly the fields firestore.rules allows
/// for each change, or the server refuses them.
void main() {
  final now = DateTime(2026, 11, 5, 10);
  final orders = {for (final o in sampleWorkOrders(now)) o.id: o};
  const doc = 'abc123';

  Set<String> keys(WorkOrder before, WorkOrder after) =>
      workOrderChanges(before, after, docId: doc).keys.toSet();

  test('start sets the status and start time only', () {
    final open = orders['WO-1047']!;
    expect(keys(open, open.start(now)), {'status', 'startedAt'});
    expect(
      workOrderChanges(open, open.start(now), docId: doc)['status'],
      'in_progress',
    );
  });

  test('submit sends the note and photo paths under work/', () {
    final working = orders['WO-1048']!;
    final submitted = working.submit(
      note: 'Fixed',
      media: ['after.jpg'],
      at: now,
    );
    final changes = workOrderChanges(working, submitted, docId: doc);
    expect(changes.keys.toSet(), {
      'status',
      'workNote',
      'workPhotos',
      'submittedAt',
    });
    expect(changes['workPhotos'], [
      'locations/marina/workOrders/abc123/work/after.jpg',
    ]);
  });

  test('confirm sends the checklist, note and inspection photos', () {
    final review = orders['WO-1043']!;
    final done = review.confirm(
      at: now,
      inspectionNote: 'Good',
      checks: ['Area clean and safe'],
      media: ['closed.jpg'],
    );
    final changes = workOrderChanges(review, done, docId: doc);
    expect(changes.keys.toSet(), {
      'status',
      'inspectionChecks',
      'inspectionNote',
      'inspectionPhotos',
      'completedAt',
    });
    expect(changes['inspectionPhotos'], [
      'locations/marina/workOrders/abc123/inspection/closed.jpg',
    ]);
  });

  test('return stores the reason code and can hand over the work', () {
    final review = orders['WO-1043']!;
    final returned = review.returnForCorrection(
      reason: 'Safety concern',
      feedback: 'Cover off',
      media: ['cover.jpg'],
      assignee: 'Tunde Bakare',
      assigneeId: 'tunde',
      at: now,
    );
    final changes = workOrderChanges(review, returned, docId: doc);
    expect(changes.keys.toSet(), {
      'status',
      'returnReason',
      'returnFeedback',
      'returnPhotos',
      'returnedAt',
      'assignedToId',
      'assignedToName',
    });
    expect(changes['returnReason'], 'safety_concern');
  });

  test('reassign sends the new technician and the note only', () {
    final open = orders['WO-1047']!;
    final moved = open.reassign(
      assignee: 'David Adeyemi',
      assigneeId: 'david',
      at: now,
      note: 'Do this first',
    );
    final changes = workOrderChanges(open, moved, docId: doc);
    expect(changes.keys.toSet(), {
      'assignedToId',
      'assignedToName',
      'assignmentNote',
    });
    expect(changes['assignedToId'], 'david');
  });

  test('server timestamps are used, never the phone clock', () {
    final open = orders['WO-1047']!;
    expect(
      workOrderChanges(open, open.start(now), docId: doc)['startedAt'],
      FieldValue.serverTimestamp(),
    );
  });

  test('timeline entries read back as the app words them', () {
    final at = Timestamp.fromDate(now);
    expect(
      eventFromDoc({'kind': 'started', 'createdAt': at}).title,
      'Technician working on it',
    );
    final assigned = eventFromDoc({
      'kind': 'reassigned',
      'createdAt': at,
      'note': 'Assigned to David Adeyemi · Overdue, do this first',
    });
    expect(assigned.title, 'Assigned to David Adeyemi');
    expect(assigned.note, 'Overdue, do this first');
    expect(
      eventFromDoc({
        'kind': 'reported',
        'createdAt': at,
        'note': 'Scheduled by SLA plan',
      }).title,
      'Scheduled by SLA plan',
    );
  });
}
