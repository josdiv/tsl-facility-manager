import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:tsl_facility_manager/app/app.dart';
import 'package:tsl_facility_manager/core/di/injection.dart';
import 'package:tsl_facility_manager/core/router/app_routes.dart';
import 'package:tsl_facility_manager/core/session/app_role.dart';

Future<void> pumpApp(
  WidgetTester tester,
  String location, {
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TslFacilityManagerApp(initialLocation: location));
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
  });

  testWidgets('staff must clock in before starting work', (tester) async {
    await pumpApp(tester, AppRoutes.staffHome);

    await tapText(tester, 'Clock');
    await tapText(tester, 'Verify & clock in');
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
      find.text('Clock in with GPS before you start work on this task.'),
      findsNothing,
    );
    await tapText(tester, 'Start work');
    expect(find.text('Mark as done & submit'), findsOneWidget);
  });

  testWidgets('Start work is disabled until staff clock in', (tester) async {
    await pumpApp(tester, AppRoutes.staffTask('WO-1047'));
    expect(
      find.text('Clock in with GPS before you start work on this task.'),
      findsOneWidget,
    );
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Start work'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('staff submission needs a note and proof, then locks', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.staffTask('WO-1048'));

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

  testWidgets('supervisor confirms only after the full checklist', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.supervisorReview,
      size: const Size(360, 2400),
    );
    expect(find.text('To review (2)'), findsOneWidget);

    await tapText(tester, 'Pump room leak check');
    expect(
      find.text('Tick every checklist item to confirm and close.'),
      findsOneWidget,
    );

    for (final check in [
      'Unit operating correctly',
      'Area clean and safe',
      'Evidence meets requirements',
    ]) {
      await tapText(tester, check);
    }
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
    await tapText(tester, 'Verify & clock in');
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
    await tapText(tester, 'Verify & clock in');
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
    expect(find.text('REQ-082 submitted for admin approval'), findsOneWidget);
    expect(find.text('2 × HVAC air filter'), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget);
  });

  testWidgets('a task opens the parts form with its work order chosen', (
    tester,
  ) async {
    await pumpApp(
      tester,
      AppRoutes.staffTask('WO-1048'),
      size: const Size(360, 1600),
    );
    expect(find.text('Location'), findsOneWidget);
    expect(find.textContaining('Marina Towers'), findsWidgets);
    await tapText(tester, 'Request parts');
    expect(find.text('WO-1048 · AHU-02 cooling fault'), findsOneWidget);
  });

  testWidgets('a supervisor stays on attendance after clocking in', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.supervisorClock);
    await tapText(tester, 'Verify & clock in');
    expect(find.text('You’re on the clock'), findsOneWidget);
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
}
