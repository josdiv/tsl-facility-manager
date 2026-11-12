import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/media_widgets.dart';
import '../../../core/widgets/page_frames.dart';

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.iconColor,
    required this.heading,
    required this.message,
    this.children = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String heading;
  final String message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 16),
        Text(heading, textAlign: TextAlign.center, style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: text.bodyMedium),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}

/// The company's account has been locked or disabled by the platform owner.
class AccountStatePage extends StatelessWidget {
  const AccountStatePage({required this.state, super.key});

  final String state;

  @override
  Widget build(BuildContext context) {
    final disabled = state == 'disabled';
    return DetailPage(
      title: disabled ? 'Account disabled' : 'Account locked',
      children: [
        _StateLayout(
          icon: disabled ? Icons.block : Icons.lock_outline,
          iconColor: AppColors.danger,
          heading: disabled
              ? 'Access has been disabled'
              : 'Your account is locked',
          message: disabled
              ? 'Your company’s account is no longer active. Sign-in is '
                    'unavailable until it is re-enabled.'
              : 'Your company’s account is temporarily locked. Your data is '
                    'safe, and access returns once it is unlocked.',
          children: [
            const InfoBanner(
              'Contact your facility administrator for help.',
              icon: Icons.support_agent,
              tone: BannerTone.neutral,
            ),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.clientLogin),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A client's report is blocked by the company's monthly work order limit.
class MonthlyLimitPage extends StatelessWidget {
  const MonthlyLimitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Report an issue',
      children: [
        _StateLayout(
          icon: Icons.hourglass_bottom,
          iconColor: AppColors.warning,
          heading: 'Monthly limit reached',
          message:
              'Your company has used all of its work orders for this month, '
              'so we can’t accept new reports right now.',
          children: [
            const InfoBanner(
              'For anything urgent, contact your facility administrator. '
              'Existing requests are not affected.',
              icon: Icons.info_outline,
              tone: BannerTone.warning,
            ),
            FilledButton(
              onPressed: () => context.go(AppRoutes.clientRequests),
              child: const Text('View my requests'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A media upload failed, or the connection dropped partway through.
class ConnectionStatePage extends StatelessWidget {
  const ConnectionStatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Upload failed',
      children: [
        _StateLayout(
          icon: Icons.cloud_off,
          iconColor: AppColors.warning,
          heading: 'Your connection dropped',
          message:
              'Your text is saved on this device. One photo didn’t '
              'finish uploading.',
          children: [
            const MediaGrid(['After-service.jpg']),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trying the upload again…')),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry upload'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Save and try later'),
            ),
          ],
        ),
      ],
    );
  }
}
