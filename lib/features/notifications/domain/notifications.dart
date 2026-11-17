import 'package:equatable/equatable.dart';

import '../../profile/domain/user_profile.dart';

/// What a notification is about, for its icon.
enum NoticeKind {
  assigned,
  returned,
  slaDue,
  submitted,
  completed,
  message,
  requisition,
  system;

  static NoticeKind fromCode(String? code) => switch (code) {
    'assigned' => assigned,
    'returned' => returned,
    'sla_due' => slaDue,
    'submitted' => submitted,
    'completed' => completed,
    'message' => message,
    'requisition' => requisition,
    _ => system,
  };
}

/// One in-app notification. Matches `users/{uid}/notifications/{id}`.
class Notice extends Equatable {
  const Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.workOrderId,
    this.read = false,
  });

  final String id;
  final NoticeKind kind;
  final String title;
  final String body;
  final DateTime createdAt;

  /// The work order's reference, such as `WO-1048`, when tapping should open
  /// it.
  final String? workOrderId;
  final bool read;

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    body,
    createdAt,
    workOrderId,
    read,
  ];
}

abstract interface class NotificationRepository {
  /// [user]'s notifications, newest first.
  Stream<List<Notice>> watch(UserProfile user);

  Future<void> markRead(UserProfile user, Notice notice);
}

/// Device registration and taps for push notifications.
abstract interface class PushService {
  /// Sets up display and tap handling. Call once at start-up.
  Future<void> initialize();

  /// Asks for permission and saves this device's token for [user].
  Future<void> bind(UserProfile user);

  /// Removes this device's token. Call before signing out.
  Future<void> unbind();

  /// Fires when a push notification is tapped.
  Stream<void> get onTapped;
}
