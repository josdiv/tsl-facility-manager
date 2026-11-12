import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../session/app_role.dart';

/// Bottom navigation for one role. Each tab keeps its own state.
class RoleShell extends StatelessWidget {
  const RoleShell({required this.role, required this.shell, super.key});

  final AppRole role;
  final StatefulNavigationShell shell;

  static const _home = NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
    label: 'Home',
  );
  static const _clock = NavigationDestination(
    icon: Icon(Icons.my_location),
    label: 'Clock',
  );

  List<NavigationDestination> get _destinations => switch (role) {
    AppRole.client => const [
      _home,
      NavigationDestination(
        icon: Icon(Icons.list_alt_outlined),
        selectedIcon: Icon(Icons.list_alt),
        label: 'Requests',
      ),
      NavigationDestination(
        icon: Icon(Icons.add_circle_outline),
        label: 'Report',
      ),
      NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: 'Messages',
      ),
    ],
    AppRole.staff => const [
      _home,
      NavigationDestination(
        icon: Icon(Icons.assignment_outlined),
        selectedIcon: Icon(Icons.assignment),
        label: 'Tasks',
      ),
      _clock,
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: 'Parts',
      ),
    ],
    AppRole.supervisor => const [
      _home,
      NavigationDestination(
        icon: Icon(Icons.fact_check_outlined),
        selectedIcon: Icon(Icons.fact_check),
        label: 'Review',
      ),
      _clock,
      NavigationDestination(
        icon: Icon(Icons.notifications_none),
        selectedIcon: Icon(Icons.notifications),
        label: 'Alerts',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
      ),
    );
  }
}
