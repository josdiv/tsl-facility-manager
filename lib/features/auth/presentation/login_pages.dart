import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/code_input.dart';
import '../../../core/widgets/eyebrow.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/labelled_field.dart';
import '../domain/auth_repository.dart';
import 'session_cubit.dart';

/// Sample mode has no real sign-in, so screens navigate themselves. With
/// Firebase, the router moves on once the session changes.
bool _isSample(BuildContext context) =>
    context.read<SessionCubit>().state.status == SessionStatus.sample;

/// Runs an account action, showing its failure. Locked or disabled company
/// accounts open their own screen. Returns whether it succeeded.
Future<bool> _attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on AuthFailure catch (failure) {
    if (!context.mounted) return false;
    if (failure.code == 'account-locked' ||
        failure.code == 'account-disabled') {
      context.push(
        AppRoutes.previewAccount(
          failure.code == 'account-locked' ? 'locked' : 'disabled',
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
    return false;
  }
}

/// A full-width button that shows a spinner while [busy].
class _BusyButton extends StatelessWidget {
  const _BusyButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

/// Decides which experience a staff credential opens. In the UI phase the
/// sample supervisor account is recognised from its address.
AppRole roleForStaffEmail(String email) =>
    email.trim().toLowerCase().startsWith('sarah')
    ? AppRole.supervisor
    : AppRole.staff;

class _LoginFrame extends StatelessWidget {
  const _LoginFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Image.asset(
                'assets/images/thick_services_logo.jpg',
                height: 56,
                alignment: Alignment.centerLeft,
                semanticLabel: 'Thick Services Ltd',
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ClientLoginPage extends StatefulWidget {
  const ClientLoginPage({super.key});

  @override
  State<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends State<ClientLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() => _busy = true);
    final sent = await _attempt(
      context,
      () => context.read<AuthRepository>().sendEmailCode(email),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent) context.push(AppRoutes.emailVerification, extra: email);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _LoginFrame(
      children: [
        const Eyebrow('Client & visitor access'),
        const SizedBox(height: 8),
        Text('Your facility, connected.', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Report an issue and follow every step of its resolution.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 24),
        Form(
          key: _form,
          child: LabelledTextField(
            label: 'Email address',
            hint: 'daniel@example.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: emailText,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ),
        _BusyButton(
          label: 'Send verification code',
          busy: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 20),
        Text(
          'No password needed. We’ll send a secure email code.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.go(AppRoutes.staffLogin),
          child: const Text('Staff or supervisor? Sign in'),
        ),
      ],
    );
  }
}

class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key});

  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _hidePassword = true;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    final signedIn = await _attempt(
      context,
      () => context.read<AuthRepository>().signInWithPassword(
        _email.text,
        _password.text,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (signedIn && _isSample(context)) {
      context.go(AppRoutes.home(roleForStaffEmail(_email.text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _LoginFrame(
      children: [
        const Eyebrow('Staff & supervisor access'),
        const SizedBox(height: 8),
        Text('Welcome back.', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Sign in to manage your tasks and keep your facility running.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 24),
        Form(
          key: _form,
          child: Column(
            children: [
              LabelledTextField(
                label: 'Email address',
                hint: 'emeka@thickservices.com',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: emailText,
              ),
              LabelledTextField(
                label: 'Password',
                hint: 'Your password',
                controller: _password,
                obscureText: _hidePassword,
                validator: (value) =>
                    requiredText(value, 'Enter your password'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => showForgotPasswordSheet(context, _email.text),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 8),
        _BusyButton(label: 'Sign in', busy: _busy, onPressed: _submit),
        const SizedBox(height: 20),
        Text(
          'Use the credentials provided by your facility administrator.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        // Test accounts are only listed in sample and emulator builds.
        if (_isSample(context))
          const InfoBanner(
            'Sample accounts, any password: emeka@thickservices.com (Staff), '
            'sarah@thickservices.com (Supervisor).',
            icon: Icons.info_outline,
            tone: BannerTone.neutral,
          )
        else if (FirebaseEnv.useEmulators)
          const InfoBanner(
            'Test accounts, password test1234: emeka@thickservices.com '
            '(Staff), sarah@thickservices.com (Supervisor).',
            icon: Icons.info_outline,
            tone: BannerTone.neutral,
          ),
        TextButton(
          onPressed: () => context.go(AppRoutes.clientLogin),
          child: const Text('Client? Report an issue'),
        ),
      ],
    );
  }
}

/// Asks for the account email and sends a reset link. Until Firebase Auth is
/// connected it only confirms on screen.
Future<void> showForgotPasswordSheet(BuildContext context, String email) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ForgotPasswordSheet(initialEmail: email.trim()),
  );
}

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final sent = await _attempt(
      context,
      () => context.read<AuthRepository>().sendPasswordReset(_email.text),
    );
    if (!sent || !mounted) return;
    Navigator.of(context).pop();
    // Same message whether or not the account exists, so the form can't be
    // used to find out who has an account.
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'If that email has an account, a reset link is on its way.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reset your password', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Enter your work email and we’ll send you a link to set a new '
              'password.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            LabelledTextField(
              label: 'Email address',
              hint: 'emeka@thickservices.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: emailText,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _send(),
            ),
            FilledButton(
              onPressed: _send,
              child: const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({required this.email, super.key});

  final String email;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  static const _length = 6;
  final _code = TextEditingController();
  var _showError = false;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (_code.text.length != _length) {
      setState(() => _showError = true);
      return;
    }
    // Close the keyboard first, so the next screen lays out at full height.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    final verified = await _attempt(
      context,
      () => context.read<AuthRepository>().verifyEmailCode(
        widget.email,
        _code.text,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!verified) {
      _code.clear(); // Ready for another try.
      return;
    }
    if (_isSample(context)) context.go(AppRoutes.clientHome);
  }

  Future<void> _resend() async {
    final sent = await _attempt(
      context,
      () => context.read<AuthRepository>().sendEmailCode(widget.email),
    );
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Email verification')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.mail_outline, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text('Check your inbox', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit code sent to\n${widget.email}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            // The sixth digit verifies the code straight away.
            CodeInput(
              controller: _code,
              length: _length,
              hasError: _showError,
              onChanged: (_) {
                if (_showError) setState(() => _showError = false);
              },
              onCompleted: (_) => _verify(),
            ),
            if (_showError) ...[
              const SizedBox(height: 8),
              const Text(
                'Enter all 6 digits to continue.',
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            _BusyButton(
              label: 'Verify & continue',
              busy: _busy,
              onPressed: _verify,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Didn’t receive a code?', style: text.bodyMedium),
                TextButton(
                  onPressed: _resend,
                  child: const Text('Resend code'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
