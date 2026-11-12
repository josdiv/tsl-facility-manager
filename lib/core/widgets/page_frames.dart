import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/profile/presentation/profile_cubit.dart';

import '../constants/app_constants.dart';
import '../router/app_routes.dart';
import '../session/app_role.dart';
import '../theme/app_colors.dart';
import 'initials_avatar.dart';

const pagePadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

/// A top-level screen inside a role's bottom navigation.
class TabPage extends StatelessWidget {
  const TabPage({
    required this.title,
    required this.role,
    required this.children,
    super.key,
  });

  final String title;
  final AppRole role;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TabPageFrame(
      title: title,
      role: role,
      child: ListView(
        padding: pagePadding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      ),
    );
  }
}

/// [TabPage] for a screen that manages its own scrolling content.
class TabPageFrame extends StatelessWidget {
  const TabPageFrame({
    required this.title,
    required this.role,
    required this.child,
    super.key,
  });

  final String title;
  final AppRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ColoredBox(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.appName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    RoleHeaderActions(role: role),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Header shortcuts: messages for Staff and Supervisors, notifications for
/// Clients and Staff, and the profile avatar for everyone.
class RoleHeaderActions extends StatelessWidget {
  const RoleHeaderActions({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (role != AppRole.client)
          IconButton(
            tooltip: 'Messages',
            onPressed: () => context.push(AppRoutes.conversations(role)),
            icon: const Icon(Icons.chat_bubble_outline, color: AppColors.body),
          ),
        if (role != AppRole.supervisor)
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push(AppRoutes.notifications(role)),
            icon: const Badge(
              smallSize: 8,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.notifications_none, color: AppColors.body),
            ),
          ),
        Tooltip(
          message: 'Profile',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(AppRoutes.profile(role)),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: InitialsAvatar(
                context.select<ProfileCubit, String>(
                  (cubit) => cubit.of(role).initials,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A pushed screen with a back button, and no bottom navigation.
class DetailPage extends StatelessWidget {
  const DetailPage({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: pagePadding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: children,
        ),
      ),
    );
  }
}
