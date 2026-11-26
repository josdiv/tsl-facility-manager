import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/key_value_row.dart';
import '../../../core/widgets/labelled_field.dart';
import '../../../core/widgets/page_frames.dart';
import '../../attendance/domain/attendance.dart';
import '../../attendance/presentation/attendance_cubit.dart';
import '../../attendance/presentation/shift_actions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/session_cubit.dart';
import '../domain/user_profile.dart';
import 'profile_cubit.dart';

/// Name and phone are editable for everyone. Clients choose their facility;
/// staff and supervisors see the one their administrator assigned.
class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.role, super.key});

  final AppRole role;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  late final UserProfile _initial = context.read<ProfileCubit>().of(
    widget.role,
  );
  late final _name = TextEditingController(text: _initial.name);
  late final _phone = TextEditingController(text: _initial.phone);
  late String _facility = _initial.facility;
  late final Future<List<Facility>> _facilities = context
      .read<ProfileCubit>()
      .facilityOptions();
  var _saving = false;
  var _deleting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final facilities = await _facilities;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<ProfileCubit>().save(
        widget.role,
        name: _name.text,
        phone: _phone.text,
        facility: _facility,
        facilityOption: facilities
            .where((f) => f.name == _facility)
            .firstOrNull,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on AuthFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Signing out mid-shift would leave the shift open, so ask first.
  Future<void> _signOut() async {
    final attendance = context.read<AttendanceCubit>();
    if (attendance.state.contains(widget.role)) {
      final choice = await showDialog<_SignOutChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('You’re still clocked in'),
          content: const Text(
            'Clock out now so your shift ends at the right time? If you only '
            'sign out, your shift stays open.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _SignOutChoice.only),
              child: const Text('Sign out only'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _SignOutChoice.clockOut),
              child: const Text('Clock out & sign out'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _SignOutChoice.clockOut) {
        final user = context.read<ProfileCubit>().of(widget.role);
        final location = context.read<LocationService>();
        try {
          // Clocking out needs the phone at the facility.
          await attendance.clockOut(user, await shiftFix(location));
        } on AttendanceFailure catch (failure) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message)));
          return;
        }
      }
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    await context.read<SessionCubit>().signOut();
    router.go(AppRoutes.login(widget.role));
  }

  /// Clients can delete their own account (staff accounts are managed in
  /// the dashboard).
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and personal details, and '
          'signs you out. Requests you have already reported stay with the '
          'facility team as part of their records. You can sign up again '
          'later with the same email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<SessionCubit>();
    try {
      await context.read<AuthRepository>().deleteAccount();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _deleting = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    await session.signOut();
    router.go(AppRoutes.login(widget.role));
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = context.select<ProfileCubit, UserProfile>(
      (cubit) => cubit.of(widget.role),
    );
    return DetailPage(
      title: 'Profile',
      children: [
        Center(child: InitialsAvatar(profile.initials, size: 64)),
        const SizedBox(height: 10),
        Text(profile.name, textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: 2),
        Text(
          widget.role.label,
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabelledTextField(
                label: 'Name',
                controller: _name,
                validator: (value) => requiredText(value, 'Enter your name'),
              ),
              LabelledTextField(
                label: 'Phone',
                controller: _phone,
                keyboardType: TextInputType.phone,
                validator: phoneText,
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyValueRow(
                      'Email',
                      profile.email,
                      divider: !canChooseFacility(widget.role),
                    ),
                    if (!canChooseFacility(widget.role)) ...[
                      KeyValueRow('Facility', profile.facility, divider: false),
                      const SizedBox(height: 8),
                      Text(
                        'Your facility is assigned by your administrator.',
                        style: text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (canChooseFacility(widget.role))
                FutureBuilder(
                  future: _facilities,
                  builder: (context, snapshot) {
                    final names = [
                      for (final f in snapshot.data ?? const <Facility>[])
                        f.name,
                    ];
                    if (names.isEmpty) return const SizedBox.shrink();
                    return LabelledDropdown(
                      label: 'Facility',
                      options: names,
                      initialValue: _facility,
                      onChanged: (value) => _facility = value,
                    );
                  },
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          onTap: () => context.push(AppRoutes.support(widget.role)),
          child: Row(
            children: [
              const Icon(Icons.support_agent, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Message support', style: text.titleSmall)),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
        // The company's own menu, for staff and supervisors.
        if (widget.role != AppRole.client) ...[
          const SizedBox(height: 12),
          AppCard(
            onTap: () => context.push(AppRoutes.more(widget.role)),
            child: Row(
              children: [
                const Icon(Icons.grid_view_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('More', style: text.titleSmall)),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        if (widget.role == AppRole.client) ...[
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _deleting ? null : _deleteAccount,
            child: Text(_deleting ? 'Deleting…' : 'Delete account'),
          ),
        ],
      ],
    );
  }
}

enum _SignOutChoice { only, clockOut }
