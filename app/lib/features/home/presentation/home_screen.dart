import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/event_model.dart';
import '../../../models/circle_model.dart';
import '../../../widgets/error_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../events/presentation/events_providers.dart';
import '../../circles/presentation/circles_providers.dart';
import 'widgets/how_it_works_card.dart';
import 'widgets/active_event_card.dart';
import 'widgets/circle_quick_start_chips.dart';

enum _HomeState { brandNew, hasCirclesNoActive, hasActiveEvents, onlyExpired }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _countdownTimer;
  bool _howItWorksDismissed = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _howItWorksDismissed = prefs.getBool('has_dismissed_how_it_works') ?? false;
        _prefsLoaded = true;
      });
    }
  }

  Future<void> _dismissHowItWorks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_dismissed_how_it_works', true);
    if (mounted) {
      setState(() => _howItWorksDismissed = true);
    }
  }

  _HomeState _computeState(List<EventModel> events, List<CircleModel> circles) {
    final activeEvents = events.where((e) => e.isActive).toList();
    if (activeEvents.isNotEmpty) return _HomeState.hasActiveEvents;
    if (circles.isEmpty && events.isEmpty) return _HomeState.brandNew;
    if (circles.isNotEmpty && activeEvents.isEmpty) {
      return events.any((e) => e.isExpired) ? _HomeState.onlyExpired : _HomeState.hasCirclesNoActive;
    }
    // Events exist but no circles (shouldn't happen, but handle gracefully)
    return events.any((e) => e.isExpired) ? _HomeState.onlyExpired : _HomeState.brandNew;
  }

  String _firstName(String displayName) {
    return displayName.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(allEventsListProvider);
    final circlesAsync = ref.watch(circlesListProvider);
    final authState = ref.watch(authStateProvider);

    final userName = authState is AuthAuthenticated ? authState.user.displayName : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            expandedHeight: 100,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0E1525),
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                child: const Text(
                  'Home',
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

          // Content — handle loading/error from both providers
          _buildContent(eventsAsync, circlesAsync, userName),
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

  Widget _buildContent(
    AsyncValue<List<EventModel>> eventsAsync,
    AsyncValue<List<CircleModel>> circlesAsync,
    String userName,
  ) {
    // If either is loading, show loading
    if (eventsAsync is AsyncLoading || circlesAsync is AsyncLoading || !_prefsLoaded) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
      );
    }

    // If either has error, show error
    if (eventsAsync is AsyncError) {
      return SliverFillRemaining(
        child: AppErrorWidget(
          message: eventsAsync.error.toString(),
          onRetry: () => ref.read(allEventsListProvider.notifier).refresh(),
        ),
      );
    }
    if (circlesAsync is AsyncError) {
      return SliverFillRemaining(
        child: AppErrorWidget(
          message: circlesAsync.error.toString(),
          onRetry: () => ref.read(circlesListProvider.notifier).refresh(),
        ),
      );
    }

    final events = eventsAsync.value ?? [];
    final circles = circlesAsync.value ?? [];
    final homeState = _computeState(events, circles);

    final activeEvents = events.where((e) => e.isActive).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    final expiredEvents = events.where((e) => e.isExpired).toList()
      ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));

    switch (homeState) {
      case _HomeState.brandNew:
        return _buildBrandNewState(userName);
      case _HomeState.hasCirclesNoActive:
        return _buildHasCirclesNoActive(circles, expiredEvents);
      case _HomeState.hasActiveEvents:
        return _buildHasActiveEvents(userName, activeEvents, expiredEvents, circles);
      case _HomeState.onlyExpired:
        return _buildOnlyExpired(circles, expiredEvents);
    }
  }

  // ── State A: Brand new user ───────────────────────────────────────────

  Widget _buildBrandNewState(String userName) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome message
            ShaderMask(
              shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
              child: const Text(
                'Welcome to\nClique Pix',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Private photo sharing that disappears',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            // How It Works card (dismissable)
            if (!_howItWorksDismissed)
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: HowItWorksCard(onDismiss: _dismissHowItWorks),
              ),
            // Primary CTA
            _buildCreateEventCTA('Create Your First Event'),
            const SizedBox(height: 16),
            Text(
              'Events let you share photos with friends.\nPhotos auto-delete when the event ends.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.3),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── State B: Has circles, no active events ────────────────────────────

  Widget _buildHasCirclesNoActive(List<CircleModel> circles, List<EventModel> expiredEvents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Heading
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Start a New Event',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.9),
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Pick a circle for your next event',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
          const SizedBox(height: 18),
          // Circle chips
          CircleQuickStartChips(circles: circles),
          const SizedBox(height: 28),
          // CTA
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildCreateEventCTA('Create Event'),
          ),
          // Past events
          if (expiredEvents.isNotEmpty) ...[
            const SizedBox(height: 36),
            _buildPastEventsSection(expiredEvents),
          ],
        ]),
      ),
    );
  }

  // ── State C: Has active events (the hot path) ─────────────────────────

  Widget _buildHasActiveEvents(
    String userName,
    List<EventModel> activeEvents,
    List<EventModel> expiredEvents,
    List<CircleModel> circles,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Greeting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Hey, ${_firstName(userName)}!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // "Live Now" section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Live Now',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.electricAqua.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    '${activeEvents.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.electricAqua,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Active event cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: activeEvents.map((e) => ActiveEventCard(event: e)).toList(),
            ),
          ),
          // Past events
          if (expiredEvents.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildPastEventsSection(expiredEvents),
          ],
        ]),
      ),
    );
  }

  // ── State D: Only expired events ──────────────────────────────────────

  Widget _buildOnlyExpired(List<CircleModel> circles, List<EventModel> expiredEvents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Encouragement
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                  child: const Text(
                    'Ready for another moment?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (expiredEvents.isNotEmpty)
                  Text(
                    'Your last event ended ${_timeAgo(expiredEvents.first.expiresAt)}',
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
                  ),
              ],
            ),
          ),
          // Circle chips (if they have circles)
          if (circles.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Pick a circle for your next event',
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
            const SizedBox(height: 12),
            CircleQuickStartChips(circles: circles),
          ],
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildCreateEventCTA('Start a New Event'),
          ),
          // Past events
          if (expiredEvents.isNotEmpty) ...[
            const SizedBox(height: 36),
            _buildPastEventsSection(expiredEvents),
          ],
        ]),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────

  Widget _buildCreateEventCTA(String label) {
    return Container(
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
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastEventsSection(List<EventModel> expiredEvents) {
    final displayEvents = expiredEvents.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Past Events',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Compact expired event rows
        ...displayEvents.map((event) => _PastEventRow(event: event)),
        // View All link
        if (expiredEvents.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: GestureDetector(
              onTap: () => context.go('/events/all'),
              child: Text(
                'View All \u2192',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.electricAqua.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }
}

class _PastEventRow extends StatelessWidget {
  final EventModel event;

  const _PastEventRow({required this.event});

  String get _expiredAgo {
    final diff = DateTime.now().difference(event.expiresAt);
    if (diff.inDays > 0) return 'Expired ${diff.inDays}d ago';
    if (diff.inHours > 0) return 'Expired ${diff.inHours}h ago';
    return 'Expired recently';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.04),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _expiredAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${event.photoCount} photos',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.3),
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
