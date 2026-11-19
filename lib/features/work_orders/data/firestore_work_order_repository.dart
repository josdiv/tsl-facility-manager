import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../../core/media/photo_service.dart';
import '../../../core/session/app_role.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/work_order.dart';
import '../domain/work_order_repository.dart';

/// Work orders in Firestore. The app knows orders by their reference
/// (`WO-1048`); this class maps references to document IDs.
///
/// Writes send only the fields a change touches, as firestore.rules requires.
/// Timeline events are written by the onWorkOrderWrite Cloud Function.
class FirestoreWorkOrderRepository implements WorkOrderRepository {
  FirestoreWorkOrderRepository({
    required PhotoService photos,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _photos = photos,
       _db = firestore ?? appFirestore(),
       _functions = functions ?? appFunctions(),
       _auth = auth ?? FirebaseAuth.instance;

  final PhotoService _photos;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Uploads any photos still on the phone to
  /// locations/{locationId}/workOrders/{docId}/{kind}/ and returns the list
  /// with their Storage paths.
  Future<List<String>> _upload(
    String? locationId,
    String docId,
    String kind,
    List<String> photos,
  ) async {
    if (!photos.any(isLocalPhoto)) return photos;
    if (locationId == null) {
      throw const WorkOrderFailure(
        'This task has no facility, so photos can’t be added.',
      );
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      // Storage checks the facility in the sign-in token, so make sure the
      // token is current before the first upload.
      await _auth.currentUser?.getIdToken(true);
      return [
        for (final (i, photo) in photos.indexed)
          isLocalPhoto(photo)
              ? await _photos.upload(
                  photo,
                  photoPath(
                    locationId,
                    docId,
                    kind,
                    '${stamp}_$i.${_extension(photo)}',
                  ),
                )
              : photo,
      ];
    } on FirebaseException {
      throw const WorkOrderFailure(
        'Your photos couldn’t upload. Check your connection and try again.',
      );
    }
  }

  static String _extension(String path) {
    final extension = path.split('.').last.toLowerCase();
    return const {
          'jpg',
          'jpeg',
          'png',
          'webp',
          'heic',
          'heif',
        }.contains(extension)
        ? extension
        : 'jpg';
  }

  /// Reference → document ID, filled as orders arrive.
  final _docIds = <String, String>{};

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('workOrders');

  /// The document ID behind a reference, once the order has been loaded.
  String? docIdFor(String ref) => _docIds[ref];

  @override
  Stream<List<WorkOrder>> watch(UserProfile? user) {
    if (user == null) return Stream.value(const []);
    final query = switch (user.role) {
      AppRole.client =>
        _orders
            .where('clientId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true),
      AppRole.staff =>
        _orders.where('assignedToId', isEqualTo: user.uid).orderBy('dueAt'),
      AppRole.supervisor =>
        _orders
            .where('locationId', isEqualTo: user.locationId)
            .orderBy('dueAt'),
    };
    return query.snapshots().map((snap) {
      final orders = <WorkOrder>[];
      for (final doc in snap.docs) {
        final order = workOrderFromDoc(doc);
        if (order == null) continue;
        _docIds[order.id] = doc.id;
        orders.add(order);
      }
      return orders;
    });
  }

  @override
  Stream<List<WorkOrderEvent>> watchHistory(String id) {
    final docId = _docIds[id];
    if (docId == null) return Stream.value(const []);
    return _orders
        .doc(docId)
        .collection('events')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => [for (final doc in snap.docs) eventFromDoc(doc.data())]);
  }

  @override
  Future<void> update(WorkOrder before, WorkOrder after) async {
    final docId = _docIds[after.id];
    final uid = _auth.currentUser?.uid;
    if (docId == null || uid == null) {
      throw WorkOrderFailure('${after.id} couldn’t be updated. Try again.');
    }
    // New photos go up first: Storage only accepts them while the order is
    // still in the status before this change.
    final uploaded = after.withMedia(
      work: await _upload(after.locationId, docId, 'work', after.workMedia),
      returned: await _upload(
        after.locationId,
        docId,
        'return',
        after.returnMedia,
      ),
      inspection: await _upload(
        after.locationId,
        docId,
        'inspection',
        after.inspectionMedia,
      ),
    );
    final changes = workOrderChanges(before, uploaded, docId: docId);
    if (changes.isEmpty) return;
    try {
      await _orders.doc(docId).update({
        ...changes,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
    } on FirebaseException catch (e) {
      throw WorkOrderFailure(
        e.code == 'permission-denied'
            ? 'You can’t make that change to ${after.id}.'
            : '${after.id} couldn’t be updated. Check your connection.',
      );
    }
  }

  @override
  Future<String> report(IssueDraft draft, UserProfile client) async {
    // The ID is chosen here so photos can be uploaded under it first.
    final docId = _orders.doc().id;
    final locationId = draft.location.id;
    final photos = await _upload(locationId, docId, 'report', draft.media);
    try {
      final result = await _functions
          .httpsCallable('reportIssue')
          .call<Object?>({
            'workOrderId': docId,
            'title': draft.title,
            'description': draft.description,
            'locationId': draft.location.id,
            'zoneId': draft.zone.id,
            'photos': [
              for (final photo in photos)
                photoPath(locationId, docId, 'report', photo),
            ],
          });
      final ref = (result.data as Map)['ref'] as String;
      _docIds[ref] = docId;
      return ref;
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'monthly-limit') {
        throw const WorkOrderFailure(
          'Your company has used all its requests for this month.',
          code: 'monthly-limit',
        );
      }
      throw WorkOrderFailure(
        e.code == 'unavailable' || e.code == 'internal'
            ? 'We couldn’t send your request. Check your connection.'
            : e.message ?? 'We couldn’t send your request.',
      );
    }
  }

  @override
  Future<List<Zone>> zones(String locationId) async {
    final snap = await _db
        .collection('zones')
        .where('locationId', isEqualTo: locationId)
        .get();
    return [
      for (final doc in snap.docs)
        if (doc.data()['status'] != 'inactive')
          Zone(doc.id, doc.data()['name'] as String),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Stream<List<TeamMember>> watchTeam(String locationId) => _db
      .collection('users')
      .where('locationId', isEqualTo: locationId)
      .where('role', isEqualTo: 'staff')
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            if (doc.data()['status'] == 'active')
              TeamMember(
                uid: doc.id,
                name: doc.data()['name'] as String,
                designation: doc.data()['designation'] as String?,
                onShift: doc.data()['onShift'] == true,
              ),
        ]..sort((a, b) => a.name.compareTo(b.name)),
      );
}

// ---------------------------------------------------------------- Mapping

const _statusCodes = {
  WorkOrderStatus.open: 'open',
  WorkOrderStatus.inProgress: 'in_progress',
  WorkOrderStatus.pendingReview: 'pending_review',
  WorkOrderStatus.returned: 'returned',
  WorkOrderStatus.completed: 'completed',
};

/// Return reasons as the app shows them, and as Firestore stores them.
const returnReasonCodes = {
  'Incomplete finishing': 'incomplete_finishing',
  'Work not satisfactory': 'not_satisfactory',
  'Safety concern': 'safety_concern',
  'Wrong resolution': 'wrong_resolution',
};

/// Storage path for a photo. Already-stored photos keep their path.
String photoPath(String? locationId, String docId, String kind, String photo) =>
    photo.startsWith('locations/')
    ? photo
    : 'locations/$locationId/workOrders/$docId/$kind/$photo';

List<String> _paths(Object? paths) => [
  for (final path in (paths as List?) ?? const []) path as String,
];

DateTime? _date(Object? value) => (value as Timestamp?)?.toDate();

/// A work order from its document. Null for statuses the app doesn't show
/// (cancelled).
WorkOrder? workOrderFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  if (d == null) return null;
  final status = _statusCodes.entries
      .where((e) => e.value == d['status'])
      .firstOrNull
      ?.key;
  if (status == null) return null;
  final reasonCode = d['returnReason'] as String?;
  return WorkOrder(
    id: d['ref'] as String? ?? doc.id,
    title: d['title'] as String? ?? '',
    description: d['description'] as String? ?? '',
    type: d['type'] == 'sla' ? WorkOrderType.sla : WorkOrderType.client,
    status: status,
    location: d['locationName'] as String? ?? '',
    zone: d['zoneName'] as String? ?? '',
    locationId: d['locationId'] as String?,
    zoneId: d['zoneId'] as String?,
    due: _date(d['dueAt']) ?? DateTime.now(),
    submittedBy: d['clientName'] as String? ?? 'SLA schedule',
    submittedById: d['clientId'] as String?,
    assignee: d['assignedToName'] as String?,
    assigneeId: d['assignedToId'] as String?,
    isHighPriority: d['priority'] == 'high' || d['priority'] == 'critical',
    reportMedia: _paths(d['reportPhotos']),
    workNote: d['workNote'] as String?,
    workMedia: _paths(d['workPhotos']),
    submittedAt: _date(d['submittedAt']),
    returnReason: returnReasonCodes.entries
        .where((e) => e.value == reasonCode)
        .firstOrNull
        ?.key,
    returnFeedback: d['returnFeedback'] as String?,
    returnMedia: _paths(d['returnPhotos']),
    inspectionNote: d['inspectionNote'] as String?,
    inspectionChecks: List<String>.from(d['inspectionChecks'] as List? ?? []),
    inspectionMedia: _paths(d['inspectionPhotos']),
    assignmentNote: d['assignmentNote'] as String?,
    lastMessageAt: _date(d['lastMessageAt']),
    lastMessagePreview: d['lastMessagePreview'] as String?,
  );
}

/// A timeline entry from `workOrders/{id}/events/{eventId}`.
WorkOrderEvent eventFromDoc(Map<String, dynamic> d) {
  final at = _date(d['createdAt']) ?? DateTime.now();
  final note = d['note'] as String?;
  return switch (d['kind']) {
    'reported' when note == 'Scheduled by SLA plan' => WorkOrderEvent(
      'Scheduled by SLA plan',
      at,
    ),
    'reported' => WorkOrderEvent('Issue reported', at),
    'assigned' || 'reassigned' => () {
      // The function writes "Assigned to <name>" then any note after " · ".
      final parts = (note ?? 'Assigned').split(' · ');
      return WorkOrderEvent(
        parts.first,
        at,
        note: parts.length > 1 ? parts.skip(1).join(' · ') : null,
      );
    }(),
    'started' => WorkOrderEvent('Technician working on it', at, note: note),
    'submitted' => WorkOrderEvent('Work submitted for review', at),
    'returned' => WorkOrderEvent('Returned for correction', at, note: note),
    'confirmed' => WorkOrderEvent('Supervisor confirmed the work', at),
    'cancelled' => WorkOrderEvent('Cancelled', at, note: note),
    _ => WorkOrderEvent('Updated', at, note: note),
  };
}

/// The fields a lifecycle change touches, ready for a Firestore update.
/// Only these fields may change, per firestore.rules.
Map<String, Object?> workOrderChanges(
  WorkOrder before,
  WorkOrder after, {
  required String docId,
}) {
  final now = FieldValue.serverTimestamp();
  final changes = <String, Object?>{};
  List<String> photos(String kind, List<String> names) => [
    for (final name in names) photoPath(after.locationId, docId, kind, name),
  ];

  if (before.status != after.status) {
    changes['status'] = _statusCodes[after.status];
    switch (after.status) {
      case WorkOrderStatus.inProgress:
        changes['startedAt'] = now;
      case WorkOrderStatus.pendingReview:
        changes['workNote'] = after.workNote;
        changes['workPhotos'] = photos('work', after.workMedia);
        changes['submittedAt'] = now;
      case WorkOrderStatus.completed:
        changes['inspectionChecks'] = after.inspectionChecks;
        changes['inspectionNote'] = after.inspectionNote;
        changes['inspectionPhotos'] = photos(
          'inspection',
          after.inspectionMedia,
        );
        changes['completedAt'] = now;
      case WorkOrderStatus.returned:
        changes['returnReason'] = returnReasonCodes[after.returnReason];
        changes['returnFeedback'] = after.returnFeedback;
        changes['returnPhotos'] = photos('return', after.returnMedia);
        changes['returnedAt'] = now;
      case WorkOrderStatus.open:
        break;
    }
  }
  if (before.assigneeId != after.assigneeId && after.assigneeId != null) {
    changes['assignedToId'] = after.assigneeId;
    changes['assignedToName'] = after.assignee;
  }
  if (before.assignmentNote != after.assignmentNote &&
      after.status != WorkOrderStatus.returned) {
    changes['assignmentNote'] = after.assignmentNote;
  }
  return changes;
}
