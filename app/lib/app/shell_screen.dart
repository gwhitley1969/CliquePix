import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_bottom_nav.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}
