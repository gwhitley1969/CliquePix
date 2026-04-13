import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/event_model.dart';
import '../../../widgets/error_widget.dart';
import 'events_providers.dart';

class EventsListScreen extends ConsumerWidget {
  final String cliqueId;
  const EventsListScreen({super.key, required this.cliqueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsListProvider(cliqueId));

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: const Text(
          'Events',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: eventsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.electricAqua),
        ),
        error: (err, _) => AppErrorWidget(
          message: err.toString(),
          onRetry: () => ref.invalidate(eventsListProvider(cliqueId)),
        ),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                      child: const Icon(Icons.event_outlined, size: 64, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No events yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create an event to start sharing photos',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.electricAqua,
            backgroundColor: const Color(0xFF1A2035),
            onRefresh: () async => ref.invalidate(eventsListProvider(cliqueId)),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: events.length,
              itemBuilder: (context, index) => _EventCard(event: events[index]),
            ),
          );
        },
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlue.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.go('/events/create?cliqueId=$cliqueId'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
          label: const Text(
            'Create Event',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  const _EventCard({required this.event});

  String get _timeRemaining {
    if (event.isExpired) return 'Expired';
    final diff = event.expiresAt.difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}d remaining';
    if (diff.inHours > 0) return '${diff.inHours}h remaining';
    return '${diff.inMinutes}m remaining';
  }

  List<Color> get _statusColors {
    if (event.isExpired) return [const Color(0xFF6B7280), const Color(0xFF374151)];
    if (event.isExpiringSoon) return [AppColors.warning, const Color(0xFFEF4444)];
    return [AppColors.electricAqua, AppColors.deepBlue];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  colors[0].withValues(alpha: 0.08),
                  colors[1].withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: colors[0].withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Event icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (event.description != null && event.description!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            event.description!,
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              event.isExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
                              size: 13,
                              color: colors[0].withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _timeRemaining,
                              style: TextStyle(fontSize: 12, color: colors[0].withValues(alpha: 0.7)),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.photo_rounded, size: 13, color: Colors.white.withValues(alpha: 0.35)),
                            const SizedBox(width: 4),
                            Text(
                              '${event.photoCount} ${event.photoCount == 1 ? 'photo' : 'photos'}',
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            if (event.videoCount > 0) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.videocam_rounded, size: 13, color: Colors.white.withValues(alpha: 0.35)),
                              const SizedBox(width: 4),
                              Text(
                                '${event.videoCount} ${event.videoCount == 1 ? 'video' : 'videos'}',
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors[0].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: colors[0].withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
