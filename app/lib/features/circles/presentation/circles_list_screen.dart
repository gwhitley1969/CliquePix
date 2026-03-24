import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/gradient_app_bar.dart';
import '../../../widgets/avatar_widget.dart';
import 'circles_providers.dart';

class CirclesListScreen extends ConsumerWidget {
  const CirclesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circlesAsync = ref.watch(circlesListProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'My Circles'),
      body: circlesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorWidget(
          message: err.toString(),
          onRetry: () => ref.read(circlesListProvider.notifier).refresh(),
        ),
        data: (circles) {
          if (circles.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.group_outlined,
              title: 'No circles yet',
              subtitle: 'Create a circle to start sharing photos with friends',
              actionText: 'Create Circle',
              onAction: () => context.go('/circles/create'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(circlesListProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.standardPadding),
              itemCount: circles.length,
              itemBuilder: (context, index) {
                final circle = circles[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: AvatarWidget(name: circle.name, size: 48),
                    title: Text(circle.name, style: AppTextStyles.heading3),
                    subtitle: Text(
                      '${circle.memberCount} member${circle.memberCount != 1 ? 's' : ''}',
                      style: AppTextStyles.caption,
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                    onTap: () => context.go('/circles/${circle.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/circles/create'),
        backgroundColor: AppColors.deepBlue,
        child: const Icon(Icons.add, color: AppColors.whiteSurface),
      ),
    );
  }
}
