import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import 'notifications_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _showClearAllDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear All Notifications?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove all notifications. This action cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(notificationsRepositoryProvider).clearAll();
        ref.invalidate(notificationsListProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear notifications: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0E1525),
            actions: [
              if (notificationsAsync.valueOrNull?.isNotEmpty ?? false)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Clear All',
                  onPressed: () => _showClearAllDialog(context, ref),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.deepBlue, AppColors.violetAccent],
                ).createShader(bounds),
                child: const Text(
                  'Notifications',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              centerTitle: true,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.violetAccent.withValues(alpha: 0.12),
                      const Color(0xFF0E1525),
                    ],
                  ),
                ),
              ),
            ),
          ),
          notificationsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.violetAccent)),
            ),
            error: (err, _) => SliverFillRemaining(
              child: AppErrorWidget(
                message: err.toString(),
                onRetry: () => ref.invalidate(notificationsListProvider),
              ),
            ),
            data: (notifications) {
              if (notifications.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [AppColors.deepBlue, AppColors.violetAccent],
                            ).createShader(bounds),
                            child: const Icon(Icons.notifications_none_rounded, size: 72, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No notifications',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "You'll be notified when new photos are shared",
                            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final n = notifications[index];
                      return Dismissible(
                        key: Key(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFFEF4444),
                          ),
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          ref.read(notificationsRepositoryProvider).deleteNotification(n.id);
                          ref.invalidate(notificationsListProvider);
                        },
                        child: _NotificationTile(
                          notification: n,
                          onTap: () {
                            ref.read(notificationsRepositoryProvider).markRead(n.id);
                            final eventId = n.payload['event_id'] as String?;
                            final circleId = n.payload['circle_id'] as String?;
                            if (eventId != null) {
                              context.push('/events/$eventId');
                            } else if (circleId != null) {
                              context.push('/circles/$circleId');
                            }
                          },
                        ),
                      );
                    },
                    childCount: notifications.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final dynamic notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  (IconData, List<Color>) get _iconAndColors {
    switch (notification.type) {
      case 'new_photo':
        return (Icons.photo_camera_rounded, [AppColors.electricAqua, AppColors.deepBlue]);
      case 'event_expiring':
        return (Icons.timer_rounded, [AppColors.warning, const Color(0xFFEF4444)]);
      case 'event_expired':
        return (Icons.timer_off_rounded, [const Color(0xFF6B7280), const Color(0xFF374151)]);
      case 'member_joined':
        return (Icons.person_add_rounded, [AppColors.electricAqua, AppColors.violetAccent]);
      default:
        return (Icons.notifications_rounded, [AppColors.deepBlue, AppColors.violetAccent]);
    }
  }

  String get _title {
    switch (notification.type) {
      case 'new_photo': return 'New Photo';
      case 'event_expiring': return 'Event Expiring Soon';
      case 'event_expired': return 'Event Expired';
      case 'member_joined': return 'New Member';
      default: return 'Notification';
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, colors) = _iconAndColors;
    final isUnread = !notification.isRead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isUnread
                  ? colors[0].withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.03),
              border: Border.all(
                color: isUnread
                    ? colors[0].withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: isUnread
                          ? colors
                          : [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.04)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(icon, color: isUnread ? Colors.white : Colors.white.withValues(alpha: 0.4), size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                          color: isUnread ? Colors.white : Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        AppDateUtils.timeAgo(notification.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
