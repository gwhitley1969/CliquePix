import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/error_widget.dart';
import '../../photos/presentation/event_feed_screen.dart';
import 'events_providers.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return eventAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: AppErrorWidget(message: err.toString())),
      data: (event) => Scaffold(
        appBar: AppBar(
          title: Text(event.name),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: event.isExpiringSoon
                    ? AppColors.warning.withValues(alpha: 0.1)
                    : AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                AppDateUtils.formatExpiry(event.expiresAt),
                style: AppTextStyles.caption.copyWith(
                  color: event.isExpiringSoon ? AppColors.warning : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: EventFeedScreen(eventId: eventId),
        floatingActionButton: event.isActive
            ? FloatingActionButton(
                onPressed: () => context.go('/events/$eventId/capture'),
                backgroundColor: AppColors.deepBlue,
                child: const Icon(Icons.camera_alt, color: AppColors.whiteSurface),
              )
            : null,
      ),
    );
  }
}
