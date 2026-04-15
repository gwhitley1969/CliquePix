import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;

  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.deepBlue.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: Colors.white.withValues(alpha: 0.4)),
            selectedIcon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.electricAqua, AppColors.deepBlue],
              ).createShader(bounds),
              child: const Icon(Icons.home_rounded, color: Colors.white),
            ),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined, color: Colors.white.withValues(alpha: 0.4)),
            selectedIcon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.deepBlue, AppColors.violetAccent],
              ).createShader(bounds),
              child: const Icon(Icons.group, color: Colors.white),
            ),
            label: 'Cliques',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined, color: Colors.white.withValues(alpha: 0.4)),
            selectedIcon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.violetAccent, Color(0xFFEC4899)],
              ).createShader(bounds),
              child: const Icon(Icons.notifications, color: Colors.white),
            ),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined, color: Colors.white.withValues(alpha: 0.4)),
            selectedIcon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFEC4899), AppColors.electricAqua],
              ).createShader(bounds),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
