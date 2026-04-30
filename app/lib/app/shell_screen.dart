import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/realtime_provider_invalidator.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    // Wrap the shell body so the realtime subscription lives for the full
    // signed-in session across all four bottom-tab branches. Invalidations
    // fire global Riverpod state changes that consumers on any screen pick
    // up on the next read.
    return Scaffold(
      body: RealtimeProviderInvalidator(child: navigationShell),
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
