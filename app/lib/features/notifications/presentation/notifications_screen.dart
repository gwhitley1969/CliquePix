import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/notification_model.dart';
import '../../../widgets/branded_sliver_app_bar.dart';
import '../../../widgets/confirm_destructive_dialog.dart';
import '../../../widgets/error_widget.dart';
import '../../photos/presentation/photos_providers.dart';
import '../../videos/presentation/videos_providers.dart';
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

  // Atomic confirm + delete for a single notification. Used by both the
  // Dismissible swipe gesture and the trailing trash IconButton in
  // `_NotificationTile`. Returns true on successful deletion (so Dismissible
  // can animate the row out), false on cancel or API failure (so Dismissible
  // snaps the row back into place).
  Future<bool> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete notification?',
      body: 'This notification will be removed from your list.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return false;
    if (!context.mounted) return false;
    try {
      await ref.read(notificationsRepositoryProvider).deleteNotification(n.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete notification: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  // Type-aware tap routing. Mirrors `_navigateFromNotification` in
  // `app/lib/services/push_notification_service.dart` — keep the two in sync.
  // `dm_message` is intentionally NOT handled here: the notifications table's
  // CHECK constraint forbids it, so a DM row can never appear in this list.
  void _handleNotificationTap(
    BuildContext context,
    WidgetRef ref,
    NotificationModel n,
  ) {
    ref.read(notificationsRepositoryProvider).markRead(n.id);

    final eventId = n.payload['event_id'] as String?;
    final cliqueId = n.payload['clique_id'] as String?;
    final photoId = n.payload['photo_id'] as String?;
    final videoId = n.payload['video_id'] as String?;

    switch (n.type) {
      case 'new_photo':
        if (eventId != null && photoId != null) {
          ref.invalidate(eventPhotosProvider(eventId));
          context.push('/events/$eventId/photos/$photoId');
          return;
        }
        break;
      case 'new_video':
      case 'video_ready':
        if (eventId != null && videoId != null) {
          ref.invalidate(eventVideosProvider(eventId));
          ref.invalidate(eventPhotosProvider(eventId));
          context.push('/events/$eventId/videos/$videoId');
          return;
        }
        break;
      case 'video_processing_failed':
      case 'event_expiring':
      case 'event_expired':
      case 'event_deleted':
        if (eventId != null) {
          context.push('/events/$eventId');
          return;
        }
        break;
      case 'member_joined':
        if (cliqueId != null) {
          context.push('/cliques/$cliqueId');
          return;
        }
        break;
    }

    // Fallback chain for unknown types or rows missing their type-specific keys.
    if (eventId != null) {
      context.push('/events/$eventId');
    } else if (cliqueId != null) {
      context.push('/cliques/$cliqueId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          BrandedSliverAppBar(
            screenTitle: 'Notifications',
            accentColor: AppColors.violetAccent,
            screenTitleGradient: const LinearGradient(
              colors: [AppColors.deepBlue, AppColors.violetAccent],
            ),
            actions: [
              if (notificationsAsync.valueOrNull?.isNotEmpty ?? false)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Clear All',
                  onPressed: () => _showClearAllDialog(context, ref),
                ),
            ],
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

              // +1 for the "Clear All" row at the top
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // First item: Clear All button row
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _showClearAllDialog(context, ref),
                                icon: Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.white.withValues(alpha: 0.6)),
                                label: Text('Clear All', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Notification tiles (offset by 1 for the Clear All row)
                      final n = notifications[index - 1];
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
                        // Confirm + delete atomically. If the API call fails or
                        // the user cancels, Dismissible snaps the row back.
                        confirmDismiss: (_) => _confirmAndDelete(context, ref, n),
                        onDismissed: (_) {
                          ref.invalidate(notificationsListProvider);
                        },
                        child: _NotificationTile(
                          notification: n,
                          onTap: () => _handleNotificationTap(context, ref, n),
                          onDelete: () => _confirmAndDelete(context, ref, n)
                              .then((deleted) {
                            if (deleted) ref.invalidate(notificationsListProvider);
                          }),
                        ),
                      );
                    },
                    childCount: notifications.length + 1, // +1 for Clear All row
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
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  (IconData, List<Color>) get _iconAndColors {
    switch (notification.type) {
      case 'new_photo':
        return (Icons.photo_camera_rounded, [AppColors.electricAqua, AppColors.deepBlue]);
      case 'new_video':
      case 'video_ready':
        return (Icons.play_circle_fill_rounded, [AppColors.deepBlue, AppColors.violetAccent]);
      case 'video_processing_failed':
        return (Icons.error_outline_rounded, [AppColors.warning, const Color(0xFFEF4444)]);
      case 'event_expiring':
        return (Icons.timer_rounded, [AppColors.warning, const Color(0xFFEF4444)]);
      case 'event_expired':
        return (Icons.timer_off_rounded, [const Color(0xFF6B7280), const Color(0xFF374151)]);
      case 'event_deleted':
        return (Icons.delete_forever_rounded, [const Color(0xFF6B7280), const Color(0xFFEF4444)]);
      case 'member_joined':
        return (Icons.person_add_rounded, [AppColors.electricAqua, AppColors.violetAccent]);
      default:
        return (Icons.notifications_rounded, [AppColors.deepBlue, AppColors.violetAccent]);
    }
  }

  String get _title {
    switch (notification.type) {
      case 'new_photo': return 'New Photo';
      case 'new_video':
      case 'video_ready': return 'New Video';
      case 'video_processing_failed': return 'Video Upload Failed';
      case 'event_expiring': return 'Event Expiring Soon';
      case 'event_expired': return 'Event Expired';
      case 'event_deleted': return 'Event Deleted';
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
        child: Row(
          children: [
            // Tap region — InkWell wraps content + unread dot only.
            // The trash IconButton lives OUTSIDE this InkWell (sibling, not
            // descendant) so its taps don't bubble up to the row tap handler.
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
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
            ),
            // Trailing trash button — discoverable per-row delete affordance.
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.45),
                  size: 22,
                ),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
