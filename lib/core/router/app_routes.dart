import '../session/app_role.dart';

abstract final class AppRoutes {
  static const clientLogin = '/login/client';
  static const emailVerification = '/login/client/verify';
  static const staffLogin = '/login/staff';

  static const clientHome = '/client/home';
  static const clientRequests = '/client/requests';
  static const clientReport = '/client/report';
  static const clientMessages = '/client/messages';

  static const staffHome = '/staff/home';
  static const staffTasks = '/staff/tasks';
  static const staffClock = '/staff/clock';
  static const staffParts = '/staff/parts';

  static const supervisorHome = '/supervisor/home';
  static const supervisorReview = '/supervisor/review';
  static const supervisorClock = '/supervisor/clock';
  static const supervisorAlerts = '/supervisor/alerts';

  /// The parts request form, optionally with a work order already chosen.
  static String staffPartsNew({String? workOrderId}) =>
      '/staff/parts/new${workOrderId == null ? '' : '?order=$workOrderId'}';

  static String clientRequest(String id) => '/client/request/$id';
  static String staffTask(String id) => '/staff/task/$id';
  static String staffSubmission(String id, {bool justSubmitted = false}) =>
      '/staff/task/$id/submission${justSubmitted ? '?new=1' : ''}';
  static String supervisorOrder(String id) => '/supervisor/order/$id';
  static String supervisorReturn(String id) => '/supervisor/order/$id/return';
  static String supervisorReassign(String id) =>
      '/supervisor/order/$id/reassign';

  static String conversations(AppRole role) =>
      role == AppRole.client ? clientMessages : '/${role.path}/conversations';
  static String chat(AppRole role, String id) => '/${role.path}/chat/$id';
  static String notifications(AppRole role) => role == AppRole.supervisor
      ? supervisorAlerts
      : '/${role.path}/notifications';
  static String profile(AppRole role) => '/${role.path}/profile';
  static String support(AppRole role) => '/${role.path}/support';

  static String previewGps(String state) => '/preview/gps/$state';
  static String previewAccount(String state) => '/preview/account/$state';
  static const previewLimit = '/preview/limit';
  static const previewConnection = '/preview/connection';

  static String home(AppRole role) => switch (role) {
    AppRole.client => clientHome,
    AppRole.staff => staffHome,
    AppRole.supervisor => supervisorHome,
  };

  static String login(AppRole role) =>
      role == AppRole.client ? clientLogin : staffLogin;
}
