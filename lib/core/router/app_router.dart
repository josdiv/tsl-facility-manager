import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/auth/presentation/login_pages.dart';
import '../../features/auth/presentation/session_cubit.dart';
import '../../features/messaging/presentation/messaging_pages.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/parts/presentation/parts_request_page.dart';
import '../../features/previews/presentation/state_pages.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/work_orders/presentation/pages/client_pages.dart';
import '../../features/work_orders/presentation/pages/staff_pages.dart';
import '../../features/work_orders/presentation/pages/supervisor_pages.dart';
import '../session/app_role.dart';
import 'app_routes.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'role_shell.dart';

StatefulShellBranch _tab(String path, Widget Function() page) =>
    StatefulShellBranch(
      routes: [GoRoute(path: path, builder: (_, _) => page())],
    );

StatefulShellRoute _shell(AppRole role, List<StatefulShellBranch> branches) =>
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => RoleShell(role: role, shell: shell),
      branches: branches,
    );

GoRoute _route(String path, Widget Function(GoRouterState state) page) =>
    GoRoute(path: path, builder: (_, state) => page(state));

/// Re-runs the router's redirect whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Stream<SessionState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Where the session allows [location] to go, or null to stay.
@visibleForTesting
String? sessionRedirect(SessionState session, String location) {
  final isLogin = location.startsWith('/login');
  final isPreview = location.startsWith('/preview');
  switch (session.status) {
    case SessionStatus.sample:
    case SessionStatus.unknown:
      return null;
    case SessionStatus.signedOut:
      return isLogin || isPreview ? null : AppRoutes.clientLogin;
    case SessionStatus.signedIn:
      final role = session.user!.role;
      final ownScreen = location.startsWith('/${role.path}/');
      if (isLogin || (!ownScreen && !isPreview)) return AppRoutes.home(role);
      return null;
  }
}

GoRouter createAppRouter({
  String initialLocation = AppRoutes.clientLogin,
  SessionCubit? session,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: session == null
        ? null
        : _SessionListenable(session.stream),
    redirect: session == null
        ? null
        : (_, state) => sessionRedirect(session.state, state.matchedLocation),
    routes: [
      _route(AppRoutes.clientLogin, (_) => const ClientLoginPage()),
      _route(
        AppRoutes.emailVerification,
        (state) => EmailVerificationPage(
          email: state.extra as String? ?? 'your email address',
        ),
      ),
      _route(AppRoutes.staffLogin, (_) => const StaffLoginPage()),

      _shell(AppRole.client, [
        _tab(AppRoutes.clientHome, () => const ClientHomePage()),
        _tab(AppRoutes.clientRequests, () => const MyRequestsPage()),
        _tab(AppRoutes.clientReport, () => const ReportIssuePage()),
        _tab(
          AppRoutes.clientMessages,
          () => const ConversationsPage(role: AppRole.client),
        ),
      ]),
      _shell(AppRole.staff, [
        _tab(AppRoutes.staffHome, () => const StaffHomePage()),
        _tab(AppRoutes.staffTasks, () => const AssignedTasksPage()),
        _tab(
          AppRoutes.staffClock,
          () => const AttendancePage(role: AppRole.staff),
        ),
        _tab(AppRoutes.staffParts, () => const PartsListPage()),
      ]),
      _shell(AppRole.supervisor, [
        _tab(AppRoutes.supervisorHome, () => const SupervisorHomePage()),
        _tab(AppRoutes.supervisorReview, () => const ReviewListPage()),
        _tab(
          AppRoutes.supervisorClock,
          () => const AttendancePage(role: AppRole.supervisor),
        ),
        _tab(
          AppRoutes.supervisorAlerts,
          () => const NotificationsPage(role: AppRole.supervisor),
        ),
      ]),

      _route(
        '/client/request/:id',
        (s) => RequestTrackingPage(id: s.pathParameters['id']!),
      ),
      _route(
        '/staff/task/:id',
        (s) => TaskEvidencePage(id: s.pathParameters['id']!),
      ),
      _route(
        '/staff/parts/new',
        (s) => PartsRequestPage(workOrderId: s.uri.queryParameters['order']),
      ),
      _route(
        '/staff/task/:id/submission',
        (s) => SubmissionPage(id: s.pathParameters['id']!),
      ),
      _route(
        '/supervisor/order/:id',
        (s) => ReviewInspectPage(id: s.pathParameters['id']!),
      ),
      _route(
        '/supervisor/order/:id/return',
        (s) => ReturnWithEvidencePage(id: s.pathParameters['id']!),
      ),
      _route(
        '/supervisor/order/:id/reassign',
        (s) => ReassignTaskPage(id: s.pathParameters['id']!),
      ),

      for (final role in [AppRole.staff, AppRole.supervisor])
        _route(
          '/${role.path}/conversations',
          (_) => ConversationsPage(role: role),
        ),
      for (final role in AppRole.values) ...[
        _route(
          '/${role.path}/chat/:id',
          (s) => ChatPage(role: role, id: s.pathParameters['id']!),
        ),
        _route('/${role.path}/profile', (_) => ProfilePage(role: role)),
        _route('/${role.path}/support', (_) => SupportChatPage(role: role)),
      ],
      for (final role in [AppRole.client, AppRole.staff])
        _route(
          '/${role.path}/notifications',
          (_) => NotificationsPage(role: role),
        ),

      _route(
        '/preview/gps/:state',
        (s) => AttendancePage(
          role: AppRole.staff,
          reading: GpsReading.fromName(s.pathParameters['state']),
          isPreview: true,
        ),
      ),
      _route(
        '/preview/account/:state',
        (s) => AccountStatePage(state: s.pathParameters['state']!),
      ),
      _route(AppRoutes.previewLimit, (_) => const MonthlyLimitPage()),
      _route(AppRoutes.previewConnection, (_) => const ConnectionStatePage()),
    ],
  );
}
