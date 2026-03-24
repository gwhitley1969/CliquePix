import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/gradient_app_bar.dart';
import 'notifications_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Notifications'),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(notificationsListProvider),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.notifications_none,
              title: 'No notifications',
              subtitle: 'You\'ll be notified when new photos are shared',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsListProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.standardPadding),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  onTap: () {
                    // Mark as read
                    ref.read(notificationsRepositoryProvider).markRead(notification.id);

                    // Navigate based on type
                    final eventId = notification.payload['event_id'] as String?;
                    if (eventId != null) {
                      context.go('/events/$eventId');
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final dynamic notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  IconData get _icon {
    switch (notification.type) {
      case 'new_photo': return Icons.photo_camera;
      case 'event_expiring': return Icons.timer;
      case 'event_expired': return Icons.timer_off;
      default: return Icons.notifications;
    }
  }

  String get _title {
    switch (notification.type) {
      case 'new_photo': return 'New Photo';
      case 'event_expiring': return 'Event Expiring Soon';
      case 'event_expired': return 'Event Expired';
      default: return 'Notification';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: notification.isRead ? AppColors.whiteSurface : AppColors.softAquaBackground,
      child: ListTile(
        leading: Icon(_icon, color: notification.isRead ? AppColors.secondaryText : AppColors.deepBlue),
        title: Text(_title, style: AppTextStyles.body.copyWith(
          fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w600,
        )),
        subtitle: Text(AppDateUtils.timeAgo(notification.createdAt), style: AppTextStyles.caption),
        trailing: notification.isRead ? null : Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(color: AppColors.deepBlue, shape: BoxShape.circle),
        ),
        onTap: onTap,
      ),
    );
  }
}
