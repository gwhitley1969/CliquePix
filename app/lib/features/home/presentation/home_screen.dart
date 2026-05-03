import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/event_model.dart';
import '../../../models/clique_model.dart';
import '../../../core/cache/last_refresh_error_provider.dart';
import '../../../widgets/branded_sliver_app_bar.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/list_skeleton.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/domain/battery_optimization_service.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../services/telemetry_service.dart';
import '../../events/presentation/events_providers.dart';
import '../../cliques/presentation/cliques_providers.dart';
import '../../profile/presentation/avatar_editor_screen.dart';
import '../../profile/presentation/avatar_picker_sheet.dart';
import '../../profile/presentation/avatar_providers.dart';
import '../../profile/presentation/widgets/avatar_welcome_prompt.dart';
import 'widgets/how_it_works_card.dart';
import 'widgets/active_event_card.dart';
import 'widgets/clique_quick_start_chips.dart';
import 'dart:io';

enum _HomeState { brandNew, hasCliquesNoActive, hasActiveEvents, onlyExpired }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _countdownTimer;
  // Default to dismissed=true so users who already cleared the banner never
  // see it flash on cold start while `_loadPrefs` resolves. The banner only
  // appears once the pref read confirms `has_dismissed_how_it_works == false`.
  bool _howItWorksDismissed = true;
  // Session-local guard — backend's `should_prompt_for_avatar` is the
  // persistent gate; this prevents re-showing the prompt if the user
  // navigates away from Home and back during the same session.
  bool _avatarPromptShown = false;
  // First-render telemetry: fired once when the screen returns non-skeleton
  // content (cached or fresh) and once when the first fresh refresh lands.
  bool _firstRenderRecorded = false;
  bool _firstFreshDataRecorded = false;
  final Stopwatch _renderClock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // Layer 1: Battery Optimization Exemption (Android only, first time only).
    // Service self-gates on `battery_dialog_shown` SharedPreferences key.
    // Also drain any telemetry events queued by isolates while the app was
    // backgrounded (WorkManager Layer 4 / FCM Layer 2 background handler).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final telemetry = ref.read(telemetryServiceProvider);
      await telemetry.drainPendingIsolateEvents();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final already = prefs.getBool('battery_dialog_shown') ?? false;
      if (already) return;
      telemetry.record('battery_exempt_prompted');
      if (!mounted) return;
      await BatteryOptimizationService().requestExemptionIfNeeded(context);
      // Check post-dialog status; fire telemetry if the user actually granted
      // the exemption. The service updates its internal SharedPreferences flag
      // regardless of outcome.
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) telemetry.record('battery_exempt_granted');
    });

    // First-sign-in avatar welcome prompt. Gated on the backend flag
    // (persistent across reinstall/devices) AND a session-local flag
    // (so navigating Home → Cliques → Home doesn't re-prompt).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _avatarPromptShown) return;
      final auth = ref.read(authStateProvider);
      if (auth is! AuthAuthenticated) return;
      if (!auth.user.shouldPromptForAvatar) return;
      _avatarPromptShown = true;
      await _showAvatarWelcomePrompt();
    });
  }

  Future<void> _showAvatarWelcomePrompt() async {
    final telemetry = ref.read(telemetryServiceProvider);
    telemetry.record('avatar_prompt_shown');
    final choice = await AvatarWelcomePrompt.show(context);
    if (!mounted) return;
    final repo = ref.read(avatarRepositoryProvider);
    switch (choice) {
      case AvatarWelcomeChoice.yes:
        // Launch the same picker/editor pipeline used from Profile.
        final pickerChoice = await AvatarPickerSheet.show(context, canRemove: false);
        if (!mounted || pickerChoice == null) return;
        final picked = pickerChoice == AvatarPickerResult.takePhoto
            ? await repo.pickFromCamera()
            : await repo.pickFromGallery();
        if (!mounted || picked == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AvatarEditorScreen(sourceFile: File(picked.path)),
          ),
        );
        break;
      case AvatarWelcomeChoice.later:
        try {
          final updated = await repo.snoozePrompt();
          if (!mounted) return;
          ref.read(authStateProvider.notifier).updateUserAvatar(updated);
          telemetry.record('avatar_prompt_snoozed');
        } catch (_) {
          // Non-fatal — user will just see the prompt again next launch.
        }
        break;
      case AvatarWelcomeChoice.no:
        try {
          final updated = await repo.dismissPrompt();
          if (!mounted) return;
          ref.read(authStateProvider.notifier).updateUserAvatar(updated);
          telemetry.record('avatar_prompt_dismissed');
        } catch (_) {
          // Non-fatal — will be re-prompted next launch, minor UX nit.
        }
        break;
    }
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

  _HomeState _computeState(List<EventModel> events, List<CliqueModel> cliques) {
    final activeEvents = events.where((e) => e.isActive).toList();
    if (activeEvents.isNotEmpty) return _HomeState.hasActiveEvents;
    if (cliques.isEmpty && events.isEmpty) return _HomeState.brandNew;
    if (cliques.isNotEmpty && activeEvents.isEmpty) {
      return events.any((e) => e.isExpired) ? _HomeState.onlyExpired : _HomeState.hasCliquesNoActive;
    }
    // Events exist but no cliques (shouldn't happen, but handle gracefully)
    return events.any((e) => e.isExpired) ? _HomeState.onlyExpired : _HomeState.brandNew;
  }

  String _firstName(String displayName) {
    return displayName.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(allEventsListProvider);
    final cliquesAsync = ref.watch(cliquesListProvider);
    final authState = ref.watch(authStateProvider);

    final userName = authState is AuthAuthenticated ? authState.user.displayName : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: CustomScrollView(
        slivers: [
          // App bar
          const BrandedSliverAppBar(
            screenTitle: 'Home',
          ),

          // Inline refresh / refresh-error pill — only renders when relevant.
          _buildRefreshPill(eventsAsync, cliquesAsync),

          // Content — handle loading/error from both providers
          _buildContent(eventsAsync, cliquesAsync, userName),
        ],
      ),
    );
  }

  Widget _buildRefreshPill(
    AsyncValue<List<EventModel>> eventsAsync,
    AsyncValue<List<CliqueModel>> cliquesAsync,
  ) {
    // Only show pills when we have data to display below them — pills above
    // a skeleton are noise.
    if (!eventsAsync.hasValue && !cliquesAsync.hasValue) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final refreshError = ref.watch(eventsRefreshErrorProvider) ??
        ref.watch(cliquesRefreshErrorProvider);
    final reloading = eventsAsync.isReloading || cliquesAsync.isReloading;
    if (!reloading && refreshError == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final isError = refreshError != null && !reloading;
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: isError
            ? () {
                ref.read(eventsRefreshErrorProvider.notifier).state = null;
                ref.read(cliquesRefreshErrorProvider.notifier).state = null;
                ref.read(allEventsListProvider.notifier).refresh();
                ref.read(cliquesListProvider.notifier).refresh();
              }
            : null,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isError
                ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
                : AppColors.electricAqua.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isError)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.electricAqua,
                  ),
                )
              else
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 14,
                  color: Color(0xFFFCA5A5),
                ),
              const SizedBox(width: 8),
              Text(
                isError ? 'Couldn\'t refresh — tap to retry' : 'Refreshing…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isError
                      ? const Color(0xFFFCA5A5)
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    AsyncValue<List<EventModel>> eventsAsync,
    AsyncValue<List<CliqueModel>> cliquesAsync,
    String userName,
  ) {
    // True first-launch path: no cache, no fresh data yet. Show a skeleton
    // instead of a full-screen blocking spinner. Returning users who have
    // cached data hit the render path below on the very first frame.
    if (!eventsAsync.hasValue && !cliquesAsync.hasValue) {
      // Only fall through to full-screen error if both providers failed AND
      // we have no cached data to render.
      if (eventsAsync.hasError) {
        return SliverFillRemaining(
          child: AppErrorWidget(
            message: eventsAsync.error.toString(),
            onRetry: () => ref.read(allEventsListProvider.notifier).refresh(),
          ),
        );
      }
      if (cliquesAsync.hasError) {
        return SliverFillRemaining(
          child: AppErrorWidget(
            message: cliquesAsync.error.toString(),
            onRetry: () => ref.read(cliquesListProvider.notifier).refresh(),
          ),
        );
      }
      return const ListSkeleton();
    }

    // Returning user (cached) OR fresh data has landed. Telemetry: fire the
    // first-render and first-fresh-data events at most once per HomeScreen
    // lifetime.
    if (!_firstRenderRecorded) {
      _firstRenderRecorded = true;
      final hadCache = eventsAsync.hasValue && eventsAsync is! AsyncLoading;
      final ms = _renderClock.elapsedMilliseconds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(telemetryServiceProvider).record(
          'home_first_render_ms',
          extra: {'ms': '$ms', 'hadCache': hadCache.toString()},
        );
      });
    }
    if (!_firstFreshDataRecorded &&
        eventsAsync.hasValue &&
        !eventsAsync.isLoading &&
        !eventsAsync.isReloading) {
      _firstFreshDataRecorded = true;
      final ms = _renderClock.elapsedMilliseconds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(telemetryServiceProvider).record(
          'home_first_fresh_data_ms',
          extra: {'ms': '$ms'},
        );
      });
    }

    final events = eventsAsync.value ?? [];
    final cliques = cliquesAsync.value ?? [];
    final homeState = _computeState(events, cliques);

    final activeEvents = events.where((e) => e.isActive).toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    final expiredEvents = events.where((e) => e.isExpired).toList()
      ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));

    switch (homeState) {
      case _HomeState.brandNew:
        return _buildBrandNewState(userName);
      case _HomeState.hasCliquesNoActive:
        return _buildHasCliquesNoActive(cliques, expiredEvents);
      case _HomeState.hasActiveEvents:
        return _buildHasActiveEvents(userName, activeEvents, expiredEvents, cliques);
      case _HomeState.onlyExpired:
        return _buildOnlyExpired(cliques, expiredEvents);
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
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── State B: Has cliques, no active events ────────────────────────────

  Widget _buildHasCliquesNoActive(List<CliqueModel> cliques, List<EventModel> expiredEvents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
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
              'Pick a clique for your next event',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
          const SizedBox(height: 18),
          // Clique chips
          CliqueQuickStartChips(cliques: cliques),
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
    List<CliqueModel> cliques,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
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
          // Create another event CTA
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildCreateEventCTA('Start Another Event'),
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

  Widget _buildOnlyExpired(List<CliqueModel> cliques, List<EventModel> expiredEvents) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
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
          // Clique chips (if they have cliques)
          if (cliques.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Pick a clique for your next event',
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
            const SizedBox(height: 12),
            CliqueQuickStartChips(cliques: cliques),
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
                Flexible(
                  child: Text(
                    event.videoCount > 0
                        ? '${event.photoCount} ${event.photoCount == 1 ? 'photo' : 'photos'} · ${event.videoCount} ${event.videoCount == 1 ? 'video' : 'videos'}'
                        : '${event.photoCount} ${event.photoCount == 1 ? 'photo' : 'photos'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    overflow: TextOverflow.ellipsis,
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
