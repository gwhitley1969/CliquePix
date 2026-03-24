import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/gradient_button.dart';
import 'circles_providers.dart';

class CircleDetailScreen extends ConsumerWidget {
  final String circleId;
  const CircleDetailScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleAsync = ref.watch(circleDetailProvider(circleId));
    final membersAsync = ref.watch(circleMembersProvider(circleId));

    return Scaffold(
      appBar: AppBar(
        title: circleAsync.when(
          data: (c) => Text(c.name),
          loading: () => const Text('Circle'),
          error: (_, __) => const Text('Circle'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => context.go('/circles/$circleId/invite'),
          ),
        ],
      ),
      body: circleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (circle) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.standardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Events section
              Card(
                child: InkWell(
                  onTap: () => context.go('/circles/$circleId/events'),
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.event, color: AppColors.deepBlue, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Events', style: AppTextStyles.heading3),
                              Text('View and create photo events', style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Members section
              Text('Members', style: AppTextStyles.heading3),
              const SizedBox(height: 12),
              membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text(err.toString()),
                data: (members) => Column(
                  children: members.map((m) => ListTile(
                    leading: AvatarWidget(name: m.displayName, imageUrl: m.avatarUrl, size: 40),
                    title: Text(m.displayName, style: AppTextStyles.body),
                    subtitle: Text(m.role == 'owner' ? 'Owner' : 'Member', style: AppTextStyles.caption),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Invite button
              GradientButton(
                text: 'Invite Friends',
                onPressed: () => context.go('/circles/$circleId/invite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
