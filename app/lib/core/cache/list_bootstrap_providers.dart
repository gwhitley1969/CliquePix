import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/clique_model.dart';
import '../../models/event_model.dart';

// Seed values read from `ListCacheService` in `main()` and overridden via
// `ProviderScope.overrides`. Null = no cache (true first launch). The
// `AsyncNotifier` for events/cliques reads these once during `build()` and
// returns the cached list synchronously, then fires a background refresh.

final eventsBootstrapProvider = Provider<List<EventModel>?>(
  (ref) => null,
  name: 'eventsBootstrapProvider',
);

final cliquesBootstrapProvider = Provider<List<CliqueModel>?>(
  (ref) => null,
  name: 'cliquesBootstrapProvider',
);

/// The user_id the events + cliques bootstrap caches were loaded for in
/// `main()`. Overridden alongside `eventsBootstrapProvider` and
/// `cliquesBootstrapProvider`; null when there was no authenticated user at
/// app startup.
///
/// Read by `AllEventsNotifier.build()` and `CliquesListNotifier.build()` to
/// fail-closed: if the bootstrap was loaded for User A but the currently-
/// authenticated user is User B (mid-session sign-out → different sign-in),
/// the bootstrap is rejected and a fresh API fetch happens instead.
///
/// The `ProviderScope.overrides` value is set ONCE at app startup and cannot
/// be re-evaluated mid-session, which is why the consumer-side comparison
/// against `currentUserIdProvider` is the load-bearing check.
final bootstrapUserIdProvider = Provider<String?>(
  (ref) => null,
  name: 'bootstrapUserIdProvider',
);
