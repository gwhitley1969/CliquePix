import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/last_refresh_error_provider.dart';
import '../../../core/cache/list_bootstrap_providers.dart';
import '../../../core/cache/list_cache_service.dart';
import '../../../models/event_model.dart';
import '../../../services/api_client.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/events_api.dart';
import '../domain/events_repository.dart';

final eventsApiProvider = Provider<EventsApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EventsApi(apiClient.dio);
});

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.watch(eventsApiProvider));
});

final allEventsListProvider =
    AsyncNotifierProvider<AllEventsNotifier, List<EventModel>>(() {
  return AllEventsNotifier();
});

class AllEventsNotifier extends AsyncNotifier<List<EventModel>> {
  @override
  Future<List<EventModel>> build() async {
    final cached = ref.read(eventsBootstrapProvider);
    if (cached != null) {
      // Stale-while-revalidate: return cached list synchronously and kick off
      // a background refresh. The microtask runs after `build` returns so the
      // first paint shows cached data immediately.
      Future.microtask(_refreshSilently);
      return cached;
    }
    return ref.read(eventsRepositoryProvider).listAllEvents();
  }

  // Manual refresh (pull-to-refresh, post-create invalidation, etc).
  // Differs from `_refreshSilently` in that it surfaces errors via
  // `AsyncError` so the screen can show its existing error widget on a
  // genuine retry path.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(eventsRepositoryProvider).listAllEvents(),
    );
    if (state.hasValue) {
      ref.read(eventsRefreshErrorProvider.notifier).state = null;
      await _writeCache(state.requireValue);
    }
  }

  // Background refresh that NEVER overwrites cached data with AsyncError —
  // a transient failure must not blank out the list the user is reading.
  // Errors are surfaced via `eventsRefreshErrorProvider` for the inline pill.
  Future<void> _refreshSilently() async {
    List<EventModel> fresh;
    try {
      fresh = await ref.read(eventsRepositoryProvider).listAllEvents();
    } catch (e) {
      debugPrint('[AllEventsNotifier] silent refresh failed: $e');
      ref.read(eventsRefreshErrorProvider.notifier).state = e;
      return; // Preserve cached AsyncData; do not push AsyncError.
    }
    state = AsyncData(fresh);
    ref.read(eventsRefreshErrorProvider.notifier).state = null;
    // Cache write is best-effort and isolated — a failure here must not
    // surface as a refresh error to the user.
    try {
      await _writeCache(fresh);
    } catch (e) {
      debugPrint('[AllEventsNotifier] cache write skipped: $e');
    }
  }

  Future<void> _writeCache(List<EventModel> events) async {
    final auth = ref.read(authStateProvider);
    if (auth is! AuthAuthenticated) return;
    await ref.read(listCacheServiceProvider).writeEvents(auth.user.id, events);
  }
}

final eventsListProvider =
    FutureProvider.family<List<EventModel>, String>((ref, cliqueId) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.listEvents(cliqueId);
});

final eventDetailProvider =
    FutureProvider.family<EventModel, String>((ref, eventId) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.getEvent(eventId);
});
