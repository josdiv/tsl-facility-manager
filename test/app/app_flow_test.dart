import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:tsl_facility_manager/app/app.dart';
import 'package:tsl_facility_manager/core/di/injection.dart';
import 'package:tsl_facility_manager/core/router/app_routes.dart';
import 'package:tsl_facility_manager/core/session/app_role.dart';
import 'package:tsl_facility_manager/features/attendance/domain/attendance.dart';
import 'package:tsl_facility_manager/features/attendance/presentation/attendance_cubit.dart';
import 'package:tsl_facility_manager/features/profile/presentation/more_page.dart';
import 'package:tsl_facility_manager/features/profile/presentation/profile_cubit.dart';

Future<void> pumpApp(
  WidgetTester tester,
  String location, {
  Size size = const Size(360, 780),
  AppRole? onShift,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TslFacilityManagerApp(initialLocation: location));
  await tester.pumpAndSettle();
  // Task actions need a started shift.
  if (onShift != null) {
    final context = tester.element(find.byType(Scaffold).first);
    await context.read<AttendanceCubit>().clockIn(
      context.read<ProfileCubit>().of(onShift),
      const LocationFix(latitude: 6.45, longitude: 3.39, accuracyM: 5),
    );
    await tester.pumpAndSettle();
  }
}

/// Taps "Verify & clock in" and confirms the dialog.
Future<void> clockIn(WidgetTester tester) async {
  await tapText(tester, 'Verify & clock in');
  expect(find.text('Clock in?'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Clock in'));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  // Long pages build lazily, so scroll until the target exists.
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterField(WidgetTester tester, String label, String value) async {
  final field = find
      .descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      )
      .first;
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

final routes = <String>[
  AppRoutes.clientLogin,
  AppRoutes.emailVerification,
  AppRoutes.staffLogin,
  AppRoutes.clientHome,
  AppRoutes.clientRequests,
  AppRoutes.clientReport,
  AppRoutes.clientMessages,
  AppRoutes.staffHome,
  AppRoutes.staffTasks,
  AppRoutes.staffClock,
  AppRoutes.staffParts,
  AppRoutes.staffPartsNew(),
  AppRoutes.supervisorHome,
  AppRoutes.supervisorReview,
  AppRoutes.supervisorClock,
  AppRoutes.supervisorAlerts,
  AppRoutes.clientRequest('WO-1048'),
  AppRoutes.staffTask('WO-1048'),
  AppRoutes.staffTask('WO-1047'),
  AppRoutes.staffSubmission('WO-1043'),
  AppRoutes.staffSubmission('WO-1041'),
  AppRoutes.supervisorOrder('WO-1043'),
  AppRoutes.supervisorOrder('WO-1047'),
  AppRoutes.supervisorReturn('WO-1043'),
  AppRoutes.supervisorReassign('WO-1043'),
  for (final role in AppRole.values) ...[
    AppRoutes.chat(role, 'WO-1048'),
    AppRoutes.profile(role),
    AppRoutes.support(role),
    AppRoutes.conversations(role),
    AppRoutes.notifications(role),
  ],
  for (final state in ['outside', 'weakSignal', 'permissionOff'])
    AppRoutes.previewGps(state),
  AppRoutes.previewAccount('locked'),
  AppRoutes.previewAccount('disabled'),
  AppRoutes.previewLimit,
  AppRoutes.previewConnection,
];

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    configureDependencies();
  });

  group('every screen renders on a small phone without overflow', () {
    for (final route in routes.toSet()) {
      testWidgets(route, (tester) async {
        await pumpApp(tester, route);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the app only ever mentions images, never videos', () {
    final video = RegExp(r'video|\.mp4', caseSensitive: false);
    for (final route in routes.toSet()) {
      testWidgets(route, (tester) async {
        // A tall viewport so the lists build everything they contain.
        await pumpApp(tester, route, size: const Size(360, 3000));
        expect(find.textContaining(video), findsNothing);
      });
    }
  });

  testWidgets('the media picker only adds photos', (tester) async {
    await pumpApp(tester, AppRoutes.clientReport, size: const Size(360, 3000));
    await tapText(tester, 'Photos');
    await tapText(tester, 'Photos');
    expect(find.text('Photo-1.jpg'), findsOneWidget);
    expect(find.text('Photo-2.jpg'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
  });

  testWidgets('the submission counts images only', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.staffSubmission('WO-1043'),
      size: const Size(360, 3000),
    );
    expect(find.text('1 image'), findsOneWidget);
  });

  testWidgets('an unknown work order shows a clear message', (tester) async {
    await pumpApp(tester, AppRoutes.staffTask('WO-9999'));
    expect(find.text('This work order could not be found.'), findsOneWidget);
  });

  testWidgets('client signs in with a code and reports an issue', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.clientLogin);

    await tapText(tester, 'Send verification code');
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await enterField(tester, 'Email address', 'daniel@example.com');
    await tapText(tester, 'Send verification code');
    expect(find.textContaining('daniel@example.com'), findsOneWidget);

    await tapText(tester, 'Verify & continue');
    expect(find.text('Enter all 6 digits to continue.'), findsOneWidget);

    // A pasted code (letters dropped) verifies without tapping the button.
    await tester.enterText(find.byType(TextField), '01-23 45');
    await tester.pumpAndSettle();
    expect(find.text('Hello, Daniel 👋'), findsOneWidget);

    await tapText(tester, 'Report');
    await tapText(tester, 'Submit issue');
    expect(find.text('Give the issue a short title'), findsOneWidget);

    await enterField(tester, 'Issue title', 'Broken window');
    await enterField(tester, 'Description', 'Reception window is cracked');
    await tapText(tester, 'Submit issue');

    expect(find.text('Request tracking'), findsOneWidget);
    expect(find.text('Broken window'), findsOneWidget);
    expect(find.textContaining('WO-1049'), findsWidgets);

    // Back goes to the client's requests, not to the form again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('My requests'), findsOneWidget);
    expect(find.text('Tell us what’s wrong'), findsNothing);
  });

  testWidgets('clients pick the equipment at fault, zone first', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.clientReport, size: const Size(360, 2400));
    expect(find.text('Asset / zone'), findsOneWidget);

    await tester.tap(find.text('Car park · Standby generator'));
    await tester.pumpAndSettle();
    for (final option in [
      'Car park · Standby generator',
      'Reception · Passenger lift 1',
      'Tower A · Floor 3 · Air handling unit AHU-02',
      'Reception · Other issue',
    ]) {
      expect(find.text(option), findsWidgets, reason: option);
    }
    await tester.tap(find.text('Reception · Passenger lift 1').last);
    await tester.pumpAndSettle();

    await enterField(tester, 'Issue title', 'Lift stuck');
    await enterField(tester, 'Description', 'Stopped between floors 2 and 3');
    await tapText(tester, 'Submit issue');
    expect(find.text('Request tracking'), findsOneWidget);
    expect(find.textContaining('Reception'), findsWidgets);
  });

  testWidgets('staff must clock in before starting work', (tester) async {
    await pumpApp(tester, AppRoutes.staffHome);

    await tapText(tester, 'Clock');
    await clockIn(tester);
    // A successful clock-in takes staff straight to their tasks.
    expect(find.text('Assigned tasks'), findsOneWidget);
    expect(find.text('Shift started · GPS verified'), findsOneWidget);

    // Open the task from its alert: in the evening its due time falls on
    // tomorrow, which moves it from the Today tab to Upcoming.
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tapText(tester, 'New assignment');
    expect(find.text('Monthly generator service'), findsOneWidget);
    expect(
      find.text('Clock in with GPS before you work on this task.'),
      findsNothing,
    );
    // Let the "Shift started" snackbar clear; it sits over the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapText(tester, 'Start work');
    expect(find.text('Mark as done & submit'), findsOneWidget);
  });

  testWidgets('every task action waits until staff clock in', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.staffTask('WO-1047'),
      size: const Size(360, 1600),
    );
    expect(
      find.text('Clock in with GPS before you work on this task.'),
      findsOneWidget,
    );
    for (final action in ['Start work', 'Message', 'Request parts']) {
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(action),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull, reason: action);
    }
  });

  testWidgets('supervisor task actions wait until they clock in', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorOrder('WO-1043'),
      size: const Size(360, 2400),
    );
    expect(
      find.text('Clock in with GPS before you work on this task.'),
      findsOneWidget,
    );
    for (final action in ['Confirm & close', 'Return', 'Reassign', 'Message']) {
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(action),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull, reason: action);
    }
  });

  testWidgets('home cards open their task tab', (tester) async {
    await pumpApp(tester, AppRoutes.staffHome);
    await tapText(tester, 'Completed');
    expect(find.text('Assigned tasks'), findsOneWidget);
    expect(find.text('Mark as done & submit'), findsNothing);
    final tabs = DefaultTabController.of(tester.element(find.byType(TabBar)));
    expect(tabs.index, 2, reason: 'Submitted tab');
  });

  testWidgets('staff submission needs a note and proof, then locks', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.staffTask('WO-1048'),
      onShift: AppRole.staff,
    );

    await tapText(tester, 'Mark as done & submit');
    expect(find.text('Describe the work you carried out'), findsOneWidget);
    expect(find.text('Add at least one photo as proof.'), findsOneWidget);

    await enterField(tester, 'Work update', 'Recharged refrigerant');
    await tapText(tester, 'Add proof of completed work');
    await tapText(tester, 'Mark as done & submit');

    expect(find.text('Work submitted'), findsOneWidget);
    expect(
      find.text('Task editing is locked until a supervisor returns it.'),
      findsOneWidget,
    );
  });

  testWidgets('supervisor confirms straight away, without a checklist', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorReview,
      size: const Size(360, 2400),
      onShift: AppRole.supervisor,
    );
    expect(find.text('To review (2)'), findsOneWidget);

    await tapText(tester, 'Pump room leak check');
    // The inspection checklist was removed for now (23 Nov 2026).
    expect(find.text('Inspection checklist'), findsNothing);
    await tapText(tester, 'Confirm & close');

    expect(find.text('To review (1)'), findsOneWidget);
    expect(find.text('WO-1043 confirmed and closed'), findsOneWidget);
  });

  testWidgets('supervisor return needs feedback and clears the queue', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorOrder('WO-1043'),
      size: const Size(360, 2400),
      onShift: AppRole.supervisor,
    );

    await tapText(tester, 'Return');
    await tapText(tester, 'Return work order');
    expect(find.text('Tell staff what to correct'), findsOneWidget);

    await enterField(tester, 'Supervisor feedback', 'Insulate the pipe');
    await tapText(tester, 'Return work order');

    expect(find.text('To review (1)'), findsOneWidget);
    expect(
      find.text('Returned to Emeka Okafor · editing unlocked'),
      findsOneWidget,
    );
  });

  testWidgets('supervisor reassigns team work with a note', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorOrder('WO-1047'),
      size: const Size(360, 1600),
      onShift: AppRole.supervisor,
    );
    await tapText(tester, 'Reassign');
    await tapText(tester, 'David Adeyemi');
    await enterField(tester, 'Assignment note', 'Overdue, do this first');
    await tapText(tester, 'Reassign & notify');

    // Back on the work order, now showing the new technician and the note.
    expect(find.text('Work order'), findsOneWidget);
    expect(find.text('David Adeyemi'), findsOneWidget);
    expect(find.textContaining('Overdue, do this first'), findsOneWidget);
    expect(
      find.text('Assigned to David Adeyemi · notification sent'),
      findsOneWidget,
    );
  });

  testWidgets('signing out mid-shift offers to clock out first', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.staffClock, size: const Size(360, 1600));
    await clockIn(tester);
    GoRouter.of(tester.element(find.text('Assigned tasks')))
        .push(AppRoutes.profile(AppRole.staff));
    await tester.pumpAndSettle();

    await tapText(tester, 'Sign out');
    expect(find.text('You’re still clocked in'), findsOneWidget);
    await tapText(tester, 'Cancel');
    expect(find.text('Profile'), findsOneWidget);

    await tapText(tester, 'Sign out');
    await tapText(tester, 'Clock out & sign out');
    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('conversations list newest first and follow new messages', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.clientMessages);
    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    // WO-1039's message is newer than WO-1048's in the sample data.
    expect(top('Washroom tap leakage'), lessThan(top('AHU-02 cooling fault')));

    await tapText(tester, 'AHU-02 cooling fault');
    await tester.enterText(find.byType(TextField), 'Still warm in here');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Still warm in here'), findsOneWidget);
    expect(top('AHU-02 cooling fault'), lessThan(top('Washroom tap leakage')));
  });

  testWidgets('a sent message appears in the conversation', (tester) async {
    await pumpApp(tester, AppRoutes.chat(AppRole.client, 'WO-1048'));
    await tester.enterText(find.byType(TextField), 'Any update?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Any update?'), findsOneWidget);
  });

  testWidgets('clients see the technician\'s work photos', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.clientRequest('WO-1043'),
      size: const Size(360, 2400),
    );
    expect(find.text('Work photos'), findsOneWidget);
  });

  testWidgets('supervisors send task messages only while clocked in', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.chat(AppRole.supervisor, 'WO-1048'));
    expect(
      find.text('Clock in to send messages about this task.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Send message'), findsNothing);

    await pumpApp(
      tester,
      AppRoutes.chat(AppRole.supervisor, 'WO-1048'),
      onShift: AppRole.supervisor,
    );
    // The team sees each sender's full name and role.
    expect(find.textContaining('Daniel Clarke · Client'), findsOneWidget);
    expect(find.textContaining('Emeka Okafor · Staff'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'On my way');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('On my way'), findsOneWidget);
  });

  testWidgets('refused clock-in cannot be submitted', (tester) async {
    await pumpApp(tester, AppRoutes.previewGps('outside'));
    expect(find.textContaining('Clock-in blocked'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping outside a field closes the keyboard', (tester) async {
    await pumpApp(tester, AppRoutes.clientLogin);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Your facility, connected.'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a field error clears once the value is corrected', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.clientLogin);
    await tapText(tester, 'Send verification code');
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await enterField(tester, 'Email address', 'daniel@example.com');
    expect(find.text('Enter a valid email address'), findsNothing);
  });

  testWidgets('a refused reading never shows an active shift', (tester) async {
    await pumpApp(tester, AppRoutes.staffClock);
    await clockIn(tester);
    expect(find.text('Assigned tasks'), findsOneWidget);

    GoRouter.of(tester.element(find.text('Assigned tasks')))
        .push(AppRoutes.previewGps('outside'));
    await tester.pumpAndSettle();
    expect(find.text('Start your shift'), findsOneWidget);
    expect(find.text('You’re on the clock'), findsNothing);
    expect(find.text('Clocked in at'), findsNothing);
  });

  testWidgets('a valid parts request is submitted and listed', (tester) async {
    await pumpApp(tester, AppRoutes.staffParts, size: const Size(360, 1600));
    expect(find.text('Pending approval'), findsNothing);
    await tapText(tester, 'Request parts');
    await tapText(tester, 'Submit requisition');
    expect(find.text('Enter a quantity of at least 1'), findsOneWidget);

    await enterField(tester, 'Quantity', '2');
    await enterField(tester, 'Reason', 'Replace damaged filters');
    await tapText(tester, 'Submit requisition');
    expect(find.text('Request submitted for admin approval'), findsOneWidget);
    expect(find.textContaining('REQ-082'), findsOneWidget);
    expect(find.text('2 × HVAC air filter'), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget);
  });

  testWidgets('supervisors request parts from their own Parts tab', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorParts,
      size: const Size(360, 1600),
    );
    expect(find.text('Parts'), findsWidgets);
    await tapText(tester, 'Request parts');
    await enterField(tester, 'Quantity', '3');
    await enterField(tester, 'Reason', 'Spare filters for the plant room');
    await tapText(tester, 'Submit requisition');
    expect(find.text('Request submitted for admin approval'), findsOneWidget);
    expect(find.text('3 × HVAC air filter'), findsOneWidget);
  });

  testWidgets('a task opens the parts form with its work order chosen', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.staffTask('WO-1048'),
      size: const Size(360, 1600),
      onShift: AppRole.staff,
    );
    expect(find.text('Location'), findsOneWidget);
    expect(find.textContaining('Marina Towers'), findsWidgets);
    await tapText(tester, 'Request parts');
    expect(find.text('WO-1048 · AHU-02 cooling fault'), findsOneWidget);
  });

  testWidgets('a supervisor goes to the review queue after clocking in', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.supervisorClock);
    await clockIn(tester);
    expect(find.text('Shift started · GPS verified'), findsOneWidget);
    expect(find.textContaining('To review'), findsOneWidget);
  });

  testWidgets('clocking in waits for confirmation', (tester) async {
    await pumpApp(tester, AppRoutes.staffClock);
    await tapText(tester, 'Verify & clock in');
    await tapText(tester, 'Cancel');
    expect(find.text('Start your shift'), findsOneWidget);
    expect(find.text('You’re on the clock'), findsNothing);
  });

  testWidgets('staff clock out from home, after confirming', (tester) async {
    await pumpApp(tester, AppRoutes.staffClock, size: const Size(360, 1600));
    await clockIn(tester);
    GoRouter.of(tester.element(find.text('Assigned tasks')))
        .go(AppRoutes.staffHome);
    await tester.pumpAndSettle();
    expect(find.text('You’re clocked in'), findsOneWidget);
    expect(find.text('View attendance'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    expect(find.text('Clock out?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clock out').last);
    await tester.pumpAndSettle();
    expect(find.text('Shift ended'), findsOneWidget);
    expect(find.text('Ready for your shift?'), findsOneWidget);
  });

  group('profile', () {
    Future<void> openProfile(WidgetTester tester, String home) async {
      await pumpApp(tester, home, size: const Size(360, 1600));
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
    }

    testWidgets('a client can choose their facility', (tester) async {
      await openProfile(tester, AppRoutes.clientHome);
      expect(find.text('Facility'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('daniel@example.com'), findsOneWidget);
      expect(find.text('Design previews'), findsNothing);

      await tapText(tester, 'Marina Towers, Lagos');
      await tapText(tester, 'Cedar Court, Abuja');
      await tapText(tester, 'Save changes');
      expect(find.text('Profile updated'), findsOneWidget);

      // The choice is kept when the profile is opened again.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Cedar Court, Abuja'), findsOneWidget);
    });

    for (final role in [AppRole.staff, AppRole.supervisor]) {
      testWidgets('${role.label} sees an assigned, read-only facility', (
        tester,
      ) async {
        await openProfile(tester, AppRoutes.home(role));
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Marina Towers, Lagos'), findsOneWidget);
        expect(
          find.text('Your facility is assigned by your administrator.'),
          findsOneWidget,
        );
        expect(find.text('Message support'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
      });
    }

    testWidgets('an edited name updates the avatar everywhere', (tester) async {
      await openProfile(tester, AppRoutes.staffHome);
      await enterField(tester, 'Name', 'Grace Eze');
      await tapText(tester, 'Save changes');
      expect(find.text('GE'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('GE'), findsOneWidget);
      expect(find.text('EO'), findsNothing);
    });

    testWidgets('name and phone are validated', (tester) async {
      await openProfile(tester, AppRoutes.staffHome);
      await enterField(tester, 'Name', '');
      await enterField(tester, 'Phone', '12ab');
      await tapText(tester, 'Save changes');
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter a valid phone number'), findsOneWidget);
      expect(find.text('Profile updated'), findsNothing);
    });

    testWidgets('message support opens a support conversation', (tester) async {
      await openProfile(tester, AppRoutes.clientHome);
      await tapText(tester, 'Message support');
      expect(find.textContaining('TSL support'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'The app froze');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('The app froze'), findsOneWidget);
    });
  });

  testWidgets('sign out returns to the right login', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.profile(AppRole.staff),
      size: const Size(360, 2400),
    );
    await tapText(tester, 'Sign out');
    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('a client can delete their account after confirming', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.profile(AppRole.client),
      size: const Size(360, 2400),
    );
    await tapText(tester, 'Delete account');
    expect(find.text('Delete your account?'), findsOneWidget);

    // Cancel keeps everything as it was.
    await tapText(tester, 'Cancel');
    expect(find.text('Delete your account?'), findsNothing);
    expect(find.text('Profile'), findsOneWidget);

    await tapText(tester, 'Delete account');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Your facility, connected.'), findsOneWidget);
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  for (final role in [AppRole.staff, AppRole.supervisor]) {
    testWidgets('${role.name} profile has a More menu', (tester) async {
      await pumpApp(
        tester,
        AppRoutes.profile(role),
        size: const Size(360, 2400),
      );
      expect(find.text('More'), findsOneWidget);
    });
  }

  testWidgets('client profile has no More menu', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.profile(AppRole.client),
      size: const Size(360, 2400),
    );
    expect(find.text('More'), findsNothing);
  });

  test('the More link carries the fixed sid and the staff email', () {
    final link = MoreMenu.linkFor('bola@thickservices.com');
    expect(
      link.toString(),
      'https://thickservices.com/TSLfacilitymanager/mwrap/index'
      '?sid=f470ea1807a7c7e8e82b7e289fdc0d5383d68e74'
      '&staffEmail=bola%40thickservices.com',
    );
    expect(link.queryParameters['staffEmail'], 'bola@thickservices.com');
  });

  testWidgets('a supervisor raises a work order and assigns a technician', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorHome,
      size: const Size(360, 2400),
      onShift: AppRole.supervisor,
    );
    await tapText(tester, 'New work order');
    expect(find.text('Raise a work order'), findsOneWidget);
    // Their own facility only.
    expect(find.text('Marina Towers, Lagos'), findsOneWidget);
    expect(find.text('Cedar Court, Abuja'), findsNothing);

    await enterField(tester, 'Issue title', 'Corridor light out');
    await enterField(tester, 'Description', 'Third floor, by the lifts');
    await tester.tap(find.text('Assign later'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emeka Okafor').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Create work order');

    expect(find.textContaining('Work order created'), findsOneWidget);
    expect(find.text('Corridor light out'), findsWidgets);
    expect(find.textContaining('Emeka Okafor'), findsWidgets);
  });

  testWidgets('clocking out goes through the same location check', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.staffClock,
      size: const Size(360, 2400),
      onShift: AppRole.staff,
    );
    expect(find.textContaining('Your shift is running'), findsOneWidget);
    expect(
      find.text('Location verified. You are inside the facility boundary.'),
      findsOneWidget,
    );
    await tapText(tester, 'Verify & clock out');
    await tester.tap(find.widgetWithText(FilledButton, 'Clock out'));
    await tester.pumpAndSettle();
    expect(find.text('Shift ended'), findsOneWidget);
  });

  testWidgets('supervisors must clock in to raise a work order', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorReport,
      size: const Size(360, 2400),
    );
    expect(
      find.text('Clock in with GPS before you work on this task.'),
      findsOneWidget,
    );
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Create work order'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('staff accounts can\'t be deleted from the app', (tester) async {
    await pumpApp(
      tester,
      AppRoutes.profile(AppRole.staff),
      size: const Size(360, 2400),
    );
    expect(find.text('Delete account'), findsNothing);
  });
}
