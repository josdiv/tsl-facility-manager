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
import '../../attendance/presentation/attendance_page.dart';
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
      if (choice == _SignOutChoice.clockOut) attendance.clockOut(widget.role);
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    await context.read<SessionCubit>().signOut();
    router.go(AppRoutes.login(widget.role));
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
        const SizedBox(height: 4),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

enum _SignOutChoice { only, clockOut }
