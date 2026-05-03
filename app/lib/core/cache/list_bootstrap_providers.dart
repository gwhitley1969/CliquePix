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
