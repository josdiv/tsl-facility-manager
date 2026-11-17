import 'package:equatable/equatable.dart';

enum WorkOrderStatus {
  open('Open'),
  inProgress('In Progress'),
  pendingReview('Pending Review'),
  returned('Returned'),
  completed('Completed');

  const WorkOrderStatus(this.label);

  final String label;

  /// Clients never see the internal return step: to them the work is ongoing.
  String get clientLabel => this == WorkOrderStatus.returned
      ? WorkOrderStatus.inProgress.label
      : label;

  bool get isActive => this != WorkOrderStatus.completed;
}

enum WorkOrderType {
  client('Client request'),
  sla('SLA maintenance');

  const WorkOrderType(this.label);

  final String label;
}

class WorkOrderEvent extends Equatable {
  const WorkOrderEvent(this.title, this.at, {this.note});

  final String title;
  final DateTime at;
  final String? note;

  @override
  List<Object?> get props => [title, at, note];
}

class WorkOrder extends Equatable {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.location,
    required this.zone,
    required this.due,
    required this.submittedBy,
    this.assignee,
    this.submittedById,
    this.assigneeId,
    this.locationId,
    this.zoneId,
    this.isHighPriority = false,
    this.reportMedia = const [],
    this.workNote,
    this.workMedia = const [],
    this.submittedAt,
    this.returnReason,
    this.returnFeedback,
    this.returnMedia = const [],
    this.inspectionNote,
    this.inspectionChecks = const [],
    this.inspectionMedia = const [],
    this.assignmentNote,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.history = const [],
  });

  final String id;
  final String title;
  final String description;
  final WorkOrderType type;
  final WorkOrderStatus status;
  final String location;
  final String zone;
  final DateTime due;
  final String submittedBy;
  final String? assignee;

  /// Account IDs behind [submittedBy] and [assignee]. Null for SLA work, which
  /// no client submits.
  final String? submittedById;
  final String? assigneeId;
  final String? locationId;
  final String? zoneId;
  final bool isHighPriority;
  final List<String> reportMedia;
  final String? workNote;
  final List<String> workMedia;
  final DateTime? submittedAt;
  final String? returnReason;
  final String? returnFeedback;
  final List<String> returnMedia;
  final String? inspectionNote;
  final List<String> inspectionChecks;
  final List<String> inspectionMedia;

  /// The supervisor's note to the technician from the last reassignment.
  final String? assignmentNote;

  /// The latest chat message on this order, for the conversation list.
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final List<WorkOrderEvent> history;

  /// Staff can only change work that is in hand or was returned to them.
  /// Submitting locks the task until a supervisor returns it.
  bool get isEditableByStaff =>
      status == WorkOrderStatus.inProgress ||
      status == WorkOrderStatus.returned;

  bool get isAwaitingReview => status == WorkOrderStatus.pendingReview;

  /// Overdue is a flag worked out from the due date, not a lifecycle status.
  /// Submitted work is with the supervisor, so it no longer counts against
  /// the technician.
  bool isOverdueAt(DateTime now) =>
      due.isBefore(now) &&
      status != WorkOrderStatus.completed &&
      status != WorkOrderStatus.pendingReview;

  WorkOrder start(DateTime at) {
    _require(status == WorkOrderStatus.open, 'start');
    return _copy(
      status: WorkOrderStatus.inProgress,
      history: [...history, WorkOrderEvent('Technician working on it', at)],
    );
  }

  WorkOrder submit({
    required String note,
    required List<String> media,
    required DateTime at,
  }) {
    _require(isEditableByStaff, 'submit');
    return _copy(
      status: WorkOrderStatus.pendingReview,
      workNote: note,
      workMedia: media,
      submittedAt: at,
      history: [...history, WorkOrderEvent('Work submitted for review', at)],
    );
  }

  WorkOrder confirm({
    required DateTime at,
    String? inspectionNote,
    List<String> checks = const [],
    List<String> media = const [],
  }) {
    _require(isAwaitingReview, 'confirm');
    return _copy(
      status: WorkOrderStatus.completed,
      inspectionNote: inspectionNote,
      inspectionChecks: checks,
      inspectionMedia: media,
      history: [
        ...history,
        WorkOrderEvent('Supervisor confirmed the work', at),
      ],
    );
  }

  WorkOrder returnForCorrection({
    required String reason,
    required String feedback,
    required List<String> media,
    required String assignee,
    required DateTime at,
    String? assigneeId,
  }) {
    _require(isAwaitingReview, 'return');
    return _copy(
      status: WorkOrderStatus.returned,
      returnReason: reason,
      returnFeedback: feedback,
      returnMedia: media,
      assignee: assignee,
      assigneeId: assigneeId,
      history: [...history, WorkOrderEvent('Returned for correction', at)],
    );
  }

  WorkOrder reassign({
    required String assignee,
    required DateTime at,
    String? assigneeId,
    String? note,
  }) {
    _require(status != WorkOrderStatus.completed, 'reassign');
    return _copy(
      assignee: assignee,
      assigneeId: assigneeId,
      assignmentNote: note,
      clearAssignmentNote: note == null,
      history: [
        ...history,
        WorkOrderEvent('Assigned to $assignee', at, note: note),
      ],
    );
  }

  void _require(bool allowed, String action) {
    if (!allowed) {
      throw StateError('Cannot $action $id while it is ${status.label}.');
    }
  }

  /// The same order with the given IDs filled in.
  WorkOrder withIds({
    String? submittedById,
    String? assigneeId,
    String? locationId,
    String? zoneId,
  }) => _copy(
    submittedById: submittedById,
    assigneeId: assigneeId,
    locationId: locationId,
    zoneId: zoneId,
  );

  /// The same order with its timeline replaced.
  WorkOrder withHistory(List<WorkOrderEvent> history) =>
      _copy(history: history);

  /// The same order with its photo lists replaced, e.g. once new photos are
  /// uploaded.
  WorkOrder withMedia({
    List<String>? report,
    List<String>? work,
    List<String>? returned,
    List<String>? inspection,
  }) => WorkOrder(
    id: id,
    title: title,
    description: description,
    type: type,
    status: status,
    location: location,
    zone: zone,
    due: due,
    submittedBy: submittedBy,
    assignee: assignee,
    submittedById: submittedById,
    assigneeId: assigneeId,
    locationId: locationId,
    zoneId: zoneId,
    isHighPriority: isHighPriority,
    reportMedia: report ?? reportMedia,
    workNote: workNote,
    workMedia: work ?? workMedia,
    submittedAt: submittedAt,
    returnReason: returnReason,
    returnFeedback: returnFeedback,
    returnMedia: returned ?? returnMedia,
    inspectionNote: inspectionNote,
    inspectionChecks: inspectionChecks,
    inspectionMedia: inspection ?? inspectionMedia,
    assignmentNote: assignmentNote,
    lastMessageAt: lastMessageAt,
    lastMessagePreview: lastMessagePreview,
    history: history,
  );

  /// The same order with a newer latest message.
  WorkOrder withLastMessage(String preview, DateTime at) =>
      _copy(lastMessagePreview: preview, lastMessageAt: at);

  WorkOrder _copy({
    WorkOrderStatus? status,
    String? assignee,
    String? assigneeId,
    String? submittedById,
    String? locationId,
    String? zoneId,
    List<String>? inspectionChecks,
    List<String>? inspectionMedia,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    String? workNote,
    List<String>? workMedia,
    DateTime? submittedAt,
    String? returnReason,
    String? returnFeedback,
    List<String>? returnMedia,
    String? inspectionNote,
    String? assignmentNote,
    bool clearAssignmentNote = false,
    List<WorkOrderEvent>? history,
  }) {
    return WorkOrder(
      id: id,
      title: title,
      description: description,
      type: type,
      status: status ?? this.status,
      location: location,
      zone: zone,
      due: due,
      submittedBy: submittedBy,
      assignee: assignee ?? this.assignee,
      submittedById: submittedById ?? this.submittedById,
      assigneeId: assigneeId ?? this.assigneeId,
      locationId: locationId ?? this.locationId,
      zoneId: zoneId ?? this.zoneId,
      isHighPriority: isHighPriority,
      reportMedia: reportMedia,
      workNote: workNote ?? this.workNote,
      workMedia: workMedia ?? this.workMedia,
      submittedAt: submittedAt ?? this.submittedAt,
      returnReason: returnReason ?? this.returnReason,
      returnFeedback: returnFeedback ?? this.returnFeedback,
      returnMedia: returnMedia ?? this.returnMedia,
      inspectionNote: inspectionNote ?? this.inspectionNote,
      inspectionChecks: inspectionChecks ?? this.inspectionChecks,
      inspectionMedia: inspectionMedia ?? this.inspectionMedia,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      assignmentNote: clearAssignmentNote
          ? null
          : assignmentNote ?? this.assignmentNote,
      history: history ?? this.history,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    type,
    status,
    location,
    zone,
    due,
    submittedBy,
    assignee,
    submittedById,
    assigneeId,
    locationId,
    zoneId,
    isHighPriority,
    reportMedia,
    workNote,
    workMedia,
    submittedAt,
    returnReason,
    returnFeedback,
    returnMedia,
    inspectionNote,
    inspectionChecks,
    inspectionMedia,
    assignmentNote,
    lastMessageAt,
    lastMessagePreview,
    history,
  ];
}
