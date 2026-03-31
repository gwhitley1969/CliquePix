import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class HowItWorksCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const HowItWorksCard({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.deepBlue.withValues(alpha: 0.1),
            AppColors.violetAccent.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(
          color: AppColors.electricAqua.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How It Works',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 20),
                const _StepRow(
                  stepNumber: '1',
                  icon: Icons.camera_alt_rounded,
                  gradientColors: [AppColors.electricAqua, AppColors.deepBlue],
                  title: 'Start an Event',
                  subtitle: 'Create a photo session for any occasion',
                ),
                const SizedBox(height: 16),
                const _StepRow(
                  stepNumber: '2',
                  icon: Icons.group_rounded,
                  gradientColors: [AppColors.deepBlue, AppColors.violetAccent],
                  title: 'Add Your Crew',
                  subtitle: 'Invite friends to your circle',
                ),
                const SizedBox(height: 16),
                const _StepRow(
                  stepNumber: '3',
                  icon: Icons.photo_library_rounded,
                  gradientColors: [AppColors.violetAccent, Color(0xFFEC4899)],
                  title: 'Snap & Share',
                  subtitle: 'Take pics — they auto-delete from the cloud when time\'s up',
                ),
              ],
            ),
          ),
          // Dismiss button
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onDismiss,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String stepNumber;
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;

  const _StepRow({
    required this.stepNumber,
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step icon with gradient background
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
