import 'dart:async';

import '../../../core/session/app_role.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/notifications.dart';

/// Sample notifications for tests and SAMPLE_DATA builds.
class InMemoryNotificationRepository implements NotificationRepository {
  InMemoryNotificationRepository({DateTime? now})
    : _now = now ?? DateTime.now();

  final DateTime _now;
  final _read = <String>{};
  final _changes = StreamController<void>.broadcast();

  List<Notice> _forRole(AppRole role) {
    DateTime ago(Duration d) => _now.subtract(d);
    final all = switch (role) {
      AppRole.client => [
        Notice(
          id: 'c1',
          kind: NoticeKind.assigned,
          title: 'Technician assigned',
          body: 'Emeka Okafor is working on WO-1048',
          workOrderId: 'WO-1048',
          createdAt: ago(const Duration(minutes: 35)),
        ),
        Notice(
          id: 'c2',
          kind: NoticeKind.completed,
          title: 'Request resolved',
          body: 'WO-1040 Office door lock repair is complete',
          workOrderId: 'WO-1040',
          createdAt: ago(const Duration(days: 3)),
        ),
      ],
      AppRole.staff => [
        Notice(
          id: 's1',
          kind: NoticeKind.slaDue,
          title: 'SLA task due',
          body: 'WO-1045 Fire extinguisher inspection · Marina Towers',
          workOrderId: 'WO-1045',
          createdAt: ago(const Duration(minutes: 12)),
        ),
        Notice(
          id: 's2',
          kind: NoticeKind.assigned,
          title: 'New assignment',
          body: 'WO-1047 Monthly generator service was assigned to you',
          workOrderId: 'WO-1047',
          createdAt: ago(const Duration(minutes: 35)),
        ),
      ],
      AppRole.supervisor => [
        Notice(
          id: 'v1',
          kind: NoticeKind.slaDue,
          title: 'SLA task overdue',
          body: 'WO-1045 Fire extinguisher inspection · Marina Towers',
          workOrderId: 'WO-1045',
          createdAt: ago(const Duration(minutes: 1)),
        ),
        Notice(
          id: 'v2',
          kind: NoticeKind.submitted,
          title: 'Work ready for review',
          body: 'Tunde Bakare submitted WO-1037 with 2 attachments',
          workOrderId: 'WO-1037',
          createdAt: ago(const Duration(minutes: 12)),
        ),
        Notice(
          id: 'v3',
          kind: NoticeKind.assigned,
          title: 'New assignment',
          body: 'WO-1047 assigned to your team',
          workOrderId: 'WO-1047',
          createdAt: ago(const Duration(minutes: 35)),
        ),
      ],
    };
    return [
      for (final n in all)
        _read.contains(n.id)
            ? Notice(
                id: n.id,
                kind: n.kind,
                title: n.title,
                body: n.body,
                workOrderId: n.workOrderId,
                createdAt: n.createdAt,
                read: true,
              )
            : n,
    ];
  }

  @override
  Stream<List<Notice>> watch(UserProfile user) async* {
    yield _forRole(user.role);
    yield* _changes.stream.map((_) => _forRole(user.role));
  }

  @override
  Future<void> markRead(UserProfile user, Notice notice) async {
    _read.add(notice.id);
    _changes.add(null);
  }
}

/// No push in sample mode.
class NoPushService implements PushService {
  const NoPushService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> bind(UserProfile user) async {}

  @override
  Future<void> unbind() async {}

  @override
  Stream<void> get onTapped => const Stream.empty();
}
