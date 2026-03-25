import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import 'events_providers.dart';

class EventsListScreen extends ConsumerWidget {
  final String circleId;
  const EventsListScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsListProvider(circleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(eventsListProvider(circleId)),
        ),
        data: (events) {
          if (events.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.event_outlined,
              title: 'No events yet',
              subtitle: 'Create an event to start sharing photos',
              actionText: 'Create Event',
              onAction: () => context.go('/circles/$circleId/events/create'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(eventsListProvider(circleId)),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.standardPadding),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => context.go('/events/${event.id}'),
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(event.name, style: AppTextStyles.heading3),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: event.isExpiringSoon
                                      ? AppColors.warning.withValues(alpha: 0.1)
                                      : event.isExpired
                                          ? AppColors.error.withValues(alpha: 0.1)
                                          : AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  AppDateUtils.formatExpiry(event.expiresAt),
                                  style: AppTextStyles.caption.copyWith(
                                    color: event.isExpiringSoon
                                        ? AppColors.warning
                                        : event.isExpired
                                            ? AppColors.error
                                            : AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (event.description != null) ...[
                            const SizedBox(height: 4),
                            Text(event.description!, style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.photo_outlined, size: 16, color: AppColors.secondaryText),
                              const SizedBox(width: 4),
                              Text('${event.photoCount} photos', style: AppTextStyles.caption),
                              const Spacer(),
                              Text(AppDateUtils.timeAgo(event.createdAt), style: AppTextStyles.caption),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/circles/$circleId/events/create'),
        backgroundColor: AppColors.deepBlue,
        child: const Icon(Icons.add, color: AppColors.whiteSurface),
      ),
    );
  }
}
