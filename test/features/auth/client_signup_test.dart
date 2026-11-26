import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tsl_facility_manager/core/router/app_routes.dart';
import 'package:tsl_facility_manager/features/auth/domain/auth_repository.dart';
import 'package:tsl_facility_manager/features/auth/presentation/login_pages.dart';
import 'package:tsl_facility_manager/features/auth/presentation/session_cubit.dart';

/// A new email: the code is accepted with a sign-up ticket.
class _NewClientAuth implements AuthRepository {
  _NewClientAuth({this.signupAllowed = true});

  final bool signupAllowed;
  final created = <Map<String, String>>[];

  @override
  Future<bool> clientSignupAllowed() async => signupAllowed;

  @override
  Future<String?> verifyEmailCode(String email, String code) async =>
      'ticket-1';

  @override
  Future<void> createClientAccount({
    required String email,
    required String ticket,
    required String name,
    required String company,
    required String phone,
  }) async {
    created.add({
      'email': email,
      'ticket': ticket,
      'name': name,
      'company': company,
      'phone': phone,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_NewClientAuth> _pumpVerify(
  WidgetTester tester, {
  bool signupAllowed = true,
}) async {
  final auth = _NewClientAuth(signupAllowed: signupAllowed);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push(AppRoutes.emailVerification),
            child: const Text('start'),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (_, _) => const EmailVerificationPage(email: 'new@x.ng'),
      ),
      GoRoute(
        path: AppRoutes.clientSignup,
        builder: (_, state) =>
            ClientSignupPage(signup: state.extra! as ClientSignup),
      ),
    ],
  );
  await tester.pumpWidget(
    RepositoryProvider<AuthRepository>.value(
      value: auth,
      child: BlocProvider(
        create: (_) => SessionCubit(auth, enforced: false),
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText).first, '123456');
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('with sign-up switched off, a new email is turned away', (
    tester,
  ) async {
    final auth = await _pumpVerify(tester, signupAllowed: false);
    expect(find.text('Tell us about you'), findsNothing);
    expect(find.textContaining('Ask your facility team'), findsOneWidget);
    expect(find.text('start'), findsOneWidget);
    expect(auth.created, isEmpty);
  });

  testWidgets('a new email verifies, then signs up with its details', (
    tester,
  ) async {
    final auth = _NewClientAuth();
    final router = GoRouter(
      initialLocation: AppRoutes.emailVerification,
      routes: [
        GoRoute(
          path: AppRoutes.emailVerification,
          builder: (_, _) => const EmailVerificationPage(email: 'new@x.ng'),
        ),
        GoRoute(
          path: AppRoutes.clientSignup,
          builder: (_, state) =>
              ClientSignupPage(signup: state.extra! as ClientSignup),
        ),
        GoRoute(
          path: AppRoutes.clientHome,
          builder: (_, _) => const Text('client home'),
        ),
      ],
    );
    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: auth,
        child: BlocProvider(
          create: (_) => SessionCubit(auth, enforced: false),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText).first, '123456');
    await tester.pumpAndSettle();
    expect(find.text('Tell us about you'), findsOneWidget);

    // Name and phone are required; the company isn't.
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a phone number'), findsOneWidget);
    expect(auth.created, isEmpty);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ada Obi');
    await tester.enterText(fields.at(2), '08030000000');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(auth.created, [
      {
        'email': 'new@x.ng',
        'ticket': 'ticket-1',
        'name': 'Ada Obi',
        'company': '',
        'phone': '08030000000',
      },
    ]);
    expect(find.text('client home'), findsOneWidget);
  });
}
