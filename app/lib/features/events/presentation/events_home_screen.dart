import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/event_model.dart';
import '../../../widgets/error_widget.dart';
import 'events_providers.dart';

class EventsHomeScreen extends ConsumerWidget {
  const EventsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(allEventsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0E1525),
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                child: const Text(
                  'My Events',
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
                      AppColors.electricAqua.withValues(alpha: 0.12),
                      const Color(0xFF0E1525),
                    ],
                  ),
                ),
              ),
            ),
          ),
          eventsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
            ),
            error: (err, _) => SliverFillRemaining(
              child: AppErrorWidget(
                message: err.toString(),
                onRetry: () => ref.read(allEventsListProvider.notifier).refresh(),
              ),
            ),
            data: (events) {
              if (events.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glowing camera icon
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.electricAqua.withValues(alpha: 0.25),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                ),
                                BoxShadow(
                                  color: AppColors.violetAccent.withValues(alpha: 0.15),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: ShaderMask(
                              shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                              child: const Icon(Icons.camera_alt_rounded, size: 80, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'No events yet',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap below to start a photo event\nwith your crew',
                            style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6), height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          // Full-width CTA button
                          Container(
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: AppGradients.primary,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.deepBlue.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => context.go('/events/create'),
                                borderRadius: BorderRadius.circular(14),
                                child: const Center(
                                  child: Text(
                                    'Create Your First Event',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Events let you share photos with friends.\nPhotos auto-delete when the event ends.',
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35), height: 1.5),
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
                    (context, index) => _EventCard(event: events[index]),
                    childCount: events.length,
                  ),
                ),
              );
            },
          ),
        ],
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
          onPressed: () => context.go('/events/create'),
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

class _CreateEventButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateEventButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Text(
              'Create Event',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            ),
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
          onTap: () => context.go('/events/${event.id}'),
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
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
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
                        const SizedBox(height: 4),
                        if (event.circleName != null)
                          Row(
                            children: [
                              Icon(Icons.group_rounded, size: 13, color: colors[0].withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(
                                event.circleName!,
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                              ),
                              if (event.memberCount != null) ...[
                                Text(
                                  ' \u00b7 ${event.memberCount} members',
                                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                                ),
                              ],
                            ],
                          ),
                        const SizedBox(height: 4),
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
                              '${event.photoCount} photos',
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                            ),
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
