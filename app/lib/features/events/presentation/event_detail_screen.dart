import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/error_widget.dart';
import '../../../models/event_model.dart';
import '../../photos/presentation/event_feed_screen.dart';
import 'events_providers.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (event) => _EventDetailBody(event: event, eventId: eventId),
      ),
    );
  }
}

class _EventDetailBody extends StatelessWidget {
  final EventModel event;
  final String eventId;
  const _EventDetailBody({required this.event, required this.eventId});

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

    return CustomScrollView(
      slivers: [
        // App bar
        SliverAppBar(
          backgroundColor: const Color(0xFF0E1525),
          foregroundColor: Colors.white,
          pinned: true,
          title: Text(
            event.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          centerTitle: true,
        ),

        // Hero header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors[0].withValues(alpha: 0.08),
                  const Color(0xFF0E1525),
                ],
              ),
            ),
            child: Column(
              children: [
                // Event name with gradient
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(colors: colors).createShader(bounds),
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (event.description != null && event.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    event.description!,
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),

                // Circle name
                if (event.circleName != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_rounded, size: 14, color: colors[0].withValues(alpha: 0.6)),
                      const SizedBox(width: 5),
                      Text(
                        event.circleName!,
                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),

                // Status badges row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatusBadge(
                      icon: event.isExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
                      label: _timeRemaining,
                      colors: colors,
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(
                      icon: Icons.photo_rounded,
                      label: '${event.photoCount} photos',
                      colors: [AppColors.deepBlue, AppColors.violetAccent],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Add Photo button (only for active events)
                if (event.isActive)
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepBlue.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.go('/events/$eventId/capture'),
                        borderRadius: BorderRadius.circular(14),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Add Photo',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Divider
                Divider(color: Colors.white.withValues(alpha: 0.06), height: 24),
              ],
            ),
          ),
        ),

        // Photo feed
        SliverFillRemaining(
          child: EventFeedScreen(eventId: eventId),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  const _StatusBadge({required this.icon, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colors[0].withValues(alpha: 0.1),
        border: Border.all(color: colors[0].withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors[0].withValues(alpha: 0.7)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors[0].withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
