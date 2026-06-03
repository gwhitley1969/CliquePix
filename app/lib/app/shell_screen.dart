import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/realtime_provider_invalidator.dart';
import '../features/paywall/presentation/paywall_providers.dart';

class ShellScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wrap the shell body so the realtime subscription lives for the full
    // signed-in session across all four bottom-tab branches. Invalidations
    // fire global Riverpod state changes that consumers on any screen pick
    // up on the next read.
    final hasAccess = ref.watch(hasAppAccessProvider);
    return Scaffold(
      body: RealtimeProviderInvalidator(child: navigationShell),
      // Hide the bottom nav when the user lacks access — the only in-shell
      // route reachable then is /profile (from the paywall's account icon).
      bottomNavigationBar: hasAccess
          ? AppBottomNav(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            )
          : null,
    );
  }
}
