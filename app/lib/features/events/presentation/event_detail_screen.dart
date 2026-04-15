import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/error_widget.dart';
import '../../../models/event_model.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../photos/presentation/event_feed_screen.dart';
import 'events_providers.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  final String? promptInviteCliqueId;
  final String? promptInviteCliqueName;
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.promptInviteCliqueId,
    this.promptInviteCliqueName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (event) => _EventDetailBody(
          event: event,
          eventId: eventId,
          promptInviteCliqueId: promptInviteCliqueId,
          promptInviteCliqueName: promptInviteCliqueName,
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/events');
              break;
            case 1:
              context.go('/cliques');
              break;
            case 2:
              context.go('/notifications');
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
      ),
    );
  }
}

class _EventDetailBody extends ConsumerStatefulWidget {
  final EventModel event;
  final String eventId;
  final String? promptInviteCliqueId;
  final String? promptInviteCliqueName;
  const _EventDetailBody({
    required this.event,
    required this.eventId,
    this.promptInviteCliqueId,
    this.promptInviteCliqueName,
  });

  @override
  ConsumerState<_EventDetailBody> createState() => _EventDetailBodyState();
}

class _EventDetailBodyState extends ConsumerState<_EventDetailBody> {
  EventModel get event => widget.event;
  String get eventId => widget.eventId;

  @override
  void initState() {
    super.initState();
    if (widget.promptInviteCliqueId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showInvitePrompt();
      });
    }
  }

  void _showInvitePrompt() {
    final cliqueId = widget.promptInviteCliqueId!;
    final cliqueName = widget.promptInviteCliqueName ?? 'your clique';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) => _InvitePromptSheet(
        cliqueName: cliqueName,
        onInvite: () {
          Navigator.pop(sheetContext);
          context.push('/invite-to-clique/$cliqueId');
        },
        onSkip: () => Navigator.pop(sheetContext),
      ),
    );
  }

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

  Future<void> _showDeleteEventDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Event?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete "${event.name}"? All photos in this event will be permanently deleted and cannot be recovered.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(eventsRepositoryProvider).deleteEvent(eventId);
        ref.invalidate(allEventsListProvider);
        ref.invalidate(eventsListProvider(event.cliqueId));
        if (mounted) {
          context.go('/events');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${event.name}" has been deleted.'),
              backgroundColor: const Color(0xFF1A2035),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete event: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors;
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final isOrganizer = event.createdByUserId == currentUserId;

    return CustomScrollView(
      slivers: [
        // App bar
        SliverAppBar(
          backgroundColor: const Color(0xFF0E1525),
          foregroundColor: Colors.white,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/events');
              }
            },
          ),
          title: Text(
            event.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.group_rounded),
              tooltip: 'View Clique',
              onPressed: () => context.push('/view-clique/${event.cliqueId}'),
            ),
            if (event.isActive)
              IconButton(
                icon: const Icon(Icons.message_rounded),
                tooltip: 'Messages',
                onPressed: () => context.push('/events/$eventId/dm-threads'),
              ),
            if (isOrganizer)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete Event',
                onPressed: _showDeleteEventDialog,
              ),
          ],
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
                // Creator name
                if (event.createdByName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_rounded, size: 14, color: colors[0].withValues(alpha: 0.6)),
                        const SizedBox(width: 5),
                        Text(
                          'Created by ${event.createdByName}',
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),

                // Clique name
                if (event.cliqueName != null)
                  GestureDetector(
                    onTap: () => context.push('/view-clique/${event.cliqueId}'),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_rounded, size: 14, color: colors[0].withValues(alpha: 0.7)),
                        const SizedBox(width: 5),
                        Text(
                          event.cliqueName!,
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                      ],
                    ),
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

                // Add Photo + Add Video buttons (only for active events)
                if (event.isActive)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
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
                              onTap: () => context.push('/events/$eventId/capture'),
                              borderRadius: BorderRadius.circular(14),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Photo',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.electricAqua, width: 2),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => context.push('/events/$eventId/video-capture'),
                              borderRadius: BorderRadius.circular(14),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.videocam_rounded, color: AppColors.electricAqua, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Video',
                                    style: TextStyle(color: AppColors.electricAqua, fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Messages button
                if (event.isActive) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.electricAqua.withValues(alpha: 0.4)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.push('/events/$eventId/dm-threads'),
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.message_rounded, color: AppColors.electricAqua, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Messages',
                              style: TextStyle(color: AppColors.electricAqua, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

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

class _InvitePromptSheet extends StatelessWidget {
  final String cliqueName;
  final VoidCallback onInvite;
  final VoidCallback onSkip;

  const _InvitePromptSheet({
    required this.cliqueName,
    required this.onInvite,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A2035),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.primary,
            ),
            child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),
          // Clique name
          ShaderMask(
            shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
            child: Text(
              cliqueName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          // Message
          Text(
            'Your clique is ready! Invite friends so they can join your events and share photos together.',
            style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6), height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Invite button
          Container(
            width: double.infinity,
            height: 52,
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
                onTap: onInvite,
                borderRadius: BorderRadius.circular(14),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Invite Friends',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Skip button
          TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip for Now',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
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
