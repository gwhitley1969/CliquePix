import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/routing/app_router.dart';
import '../main.dart' show performDeferredInit;
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_providers.dart';
// Imports below are needed solely for the user-scoped state invalidation that
// runs when the authenticated identity changes. See `_invalidateUserScopedState`
// for the rationale; without this, an iPhone user signing out and a new user
// signing up on the same device sees the prior user's events / photos / etc.
import '../features/cliques/presentation/cliques_providers.dart';
import '../features/dm/presentation/dm_providers.dart';
import '../features/events/presentation/events_providers.dart';
import '../features/notifications/presentation/notifications_providers.dart';
import '../features/photos/presentation/photos_providers.dart';
import '../features/videos/presentation/videos_providers.dart';

class CliquePix extends ConsumerStatefulWidget {
  const CliquePix({super.key});

  @override
  ConsumerState<CliquePix> createState() => _CliquePixState();
}

class _CliquePixState extends ConsumerState<CliquePix> {
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    final router = ref.read(routerProvider);
    ref.read(deepLinkServiceProvider).initialize(router);

    // Defer Workmanager + flutter_local_notifications + tz seeding to a
    // post-frame callback. None of these gate Home rendering, and pulling
    // them out of `main()` shaves 5–10 s off cold-start first paint. See
    // `performDeferredInit` in `main.dart`.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await performDeferredInit();
      } catch (e) {
        debugPrint('[CliquePix] deferred init failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final authState = ref.watch(authStateProvider);

    // Invalidate user-scoped Riverpod state when the authenticated identity
    // changes. Listening on `currentUserIdProvider` (derived String?) means we
    // only fire on actual user_id changes — not on AuthState instance churn
    // from background-verify refreshes of the same user.
    //
    // Guard `previous != null && previous != next` so we only invalidate when
    // transitioning OUT of (or BETWEEN) authenticated identities. This skips:
    //   - first sign-in from a clean app (cold-start unauth → userA): nothing
    //     to invalidate
    //   - the AuthLoading dip during interactive sign-in (userA → null →
    //     userB): the userA → null edge fires once; the null → userB edge is
    //     suppressed by the guard
    //   - Welcome Back re-auth as the same user (null → userA): no spurious
    //     invalidation
    //
    // Without this listener, after User A signs out and User B signs up on the
    // same device, every AsyncNotifier / FutureProvider.family in the data
    // layer retains User A's cached state (events, cliques, photos, videos,
    // DMs, notifications) — User B sees User A's content. This was the iOS
    // cross-account data leak reported 2026-05-06.
    ref.listen<String?>(currentUserIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        _invalidateUserScopedState(ref);
      }
    });

    // Defer push init by one frame so the FCM permission UIAlertController is
    // presented after Safari (SFSafariViewController) has fully dismissed and
    // Flutter's view controller has re-attached to the UIWindow. Calling
    // initialize() synchronously inside build() right after Safari closes was
    // observed to terminate the app on iOS first-install.
    if (authState is AuthAuthenticated && !_pushInitialized) {
      _pushInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await ref.read(pushNotificationServiceProvider).initialize();
        } catch (e) {
          debugPrint('[CliquePix] Push init failed (non-fatal): $e');
        }
      });
    }

    return MaterialApp.router(
      title: 'Clique Pix',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }

  /// Invalidates every user-scoped Riverpod provider and clears Flutter's
  /// in-memory image cache. Called by the `ref.listen` above on identity
  /// change (User A signs out / a different user signs in).
  ///
  /// Riverpod 2.x detail: `ref.invalidate(family)` (no parameter) invalidates
  /// every keyed instance of a family at once.
  ///
  /// We deliberately do NOT clear the `cached_network_image` disk cache here.
  /// That would require adding `flutter_cache_manager` as a direct dep
  /// (it's transitive via `cached_network_image`, which Dart cannot import
  /// directly). With every photo/video data provider invalidated, User B's UI
  /// never receives a `PhotoModel` carrying User A's photo_id — so the disk
  /// cache is unreachable to User B in practice. The in-memory `imageCache`
  /// clear here is defense-in-depth for any decoded image still pinned in RAM.
  void _invalidateUserScopedState(WidgetRef ref) {
    debugPrint('[AUTH] invalidating user-scoped state on identity change');
    // Events
    ref.invalidate(allEventsListProvider);
    ref.invalidate(eventsListProvider);
    ref.invalidate(eventDetailProvider);
    // Cliques
    ref.invalidate(cliquesListProvider);
    ref.invalidate(cliqueDetailProvider);
    ref.invalidate(cliqueMembersProvider);
    // Photos
    ref.invalidate(eventPhotosProvider);
    ref.invalidate(photoDetailProvider);
    ref.invalidate(mediaSelectionProvider);
    // Videos
    ref.invalidate(eventVideosProvider);
    ref.invalidate(videoDetailProvider);
    ref.invalidate(videoPlaybackProvider);
    ref.invalidate(localPendingVideosProvider);
    // Notifications
    ref.invalidate(notificationsListProvider);
    // DM
    ref.invalidate(dmThreadsProvider);
    ref.invalidate(dmThreadDetailProvider);
    ref.invalidate(dmMessagesProvider);
    // In-memory image cache (no disk dep — `painting.dart` is in flutter SDK)
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
