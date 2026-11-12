import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/key_value_row.dart';
import '../../../core/widgets/page_frames.dart';
import '../../../core/widgets/section_header.dart';

/// Gap in the design: no screen offered profile details or sign out.
class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.role, super.key});

  final AppRole role;

  (String, String) get _identity => switch (role) {
    AppRole.client => ('Daniel Clarke', 'daniel@example.com'),
    AppRole.staff => ('Emeka Okafor', 'emeka@thickservices.com'),
    AppRole.supervisor => ('Sarah James', 'sarah@thickservices.com'),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (name, email) = _identity;
    return DetailPage(
      title: 'Profile',
      children: [
        AppCard(
          child: Column(
            children: [
              InitialsAvatar(sampleInitials(role), size: 64),
              const SizedBox(height: 12),
              Text(name, style: text.titleLarge),
              const SizedBox(height: 2),
              Text(role.label, style: text.bodyMedium),
              const SizedBox(height: 8),
              KeyValueRow('Email', email),
              const KeyValueRow('Facility', 'Marina Towers, Lagos'),
            ],
          ),
        ),
        const SectionHeader('Design previews'),
        Text(
          'Edge cases for review during the UI phase. These appear on their '
          'own once the app is connected.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 8),
        _PreviewLink(
          'Clock-in: outside the geofence',
          AppRoutes.previewGps('outside'),
        ),
        _PreviewLink('Clock-in: weak GPS', AppRoutes.previewGps('weakSignal')),
        _PreviewLink(
          'Clock-in: location permission off',
          AppRoutes.previewGps('permissionOff'),
        ),
        _PreviewLink('Account locked', AppRoutes.previewAccount('locked')),
        _PreviewLink('Account disabled', AppRoutes.previewAccount('disabled')),
        const _PreviewLink('Monthly limit reached', AppRoutes.previewLimit),
        const _PreviewLink('Upload failed', AppRoutes.previewConnection),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => context.go(AppRoutes.login(role)),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _PreviewLink extends StatelessWidget {
  const _PreviewLink(this.label, this.route);

  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => context.push(route),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}
