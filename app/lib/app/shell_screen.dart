import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: Border(
            top: BorderSide(
              color: AppColors.deepBlue.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
          },
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AppColors.deepBlue.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.group_outlined, color: Colors.white.withValues(alpha: 0.4)),
              selectedIcon: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.electricAqua, AppColors.deepBlue],
                ).createShader(bounds),
                child: const Icon(Icons.group, color: Colors.white),
              ),
              label: 'Circles',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined, color: Colors.white.withValues(alpha: 0.4)),
              selectedIcon: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.deepBlue, AppColors.violetAccent],
                ).createShader(bounds),
                child: const Icon(Icons.notifications, color: Colors.white),
              ),
              label: 'Notifications',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outlined, color: Colors.white.withValues(alpha: 0.4)),
              selectedIcon: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.violetAccent, Color(0xFFEC4899)],
                ).createShader(bounds),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
