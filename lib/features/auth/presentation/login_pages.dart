import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/eyebrow.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/labelled_field.dart';

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

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    context.push(AppRoutes.emailVerification, extra: _email.text.trim());
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
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Send verification code'),
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

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    context.go(AppRoutes.home(roleForStaffEmail(_email.text)));
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
                obscureText: true,
                validator: (value) =>
                    requiredText(value, 'Enter your password'),
              ),
            ],
          ),
        ),
        FilledButton(onPressed: _submit, child: const Text('Sign in')),
        const SizedBox(height: 20),
        Text(
          'Use the credentials provided by your facility administrator.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        const InfoBanner(
          'Sample accounts, any password: emeka@thickservices.com (Staff), '
          'sarah@thickservices.com (Supervisor).',
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

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({required this.email, super.key});

  final String email;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  static const _length = 6;
  final _controllers = List.generate(_length, (_) => TextEditingController());
  final _focus = List.generate(_length, (_) => FocusNode());
  var _showError = false;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  void _onDigit(int index, String value) {
    if (value.isNotEmpty && index < _length - 1) {
      _focus[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focus[index - 1].requestFocus();
    }
    if (_showError) setState(() => _showError = false);
  }

  void _verify() {
    final complete = _controllers.every((c) => c.text.length == 1);
    if (!complete) {
      setState(() => _showError = true);
      return;
    }
    context.go(AppRoutes.clientHome);
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
            Row(
              children: [
                for (var i = 0; i < _length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: 'Code digit ${i + 1}',
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focus[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: text.titleLarge,
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onChanged: (value) => _onDigit(i, value),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_showError) ...[
              const SizedBox(height: 8),
              const Text(
                'Enter all 6 digits to continue.',
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _verify,
              child: const Text('Verify & continue'),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Didn’t receive a code?', style: text.bodyMedium),
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('A new code has been sent.')),
                  ),
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
