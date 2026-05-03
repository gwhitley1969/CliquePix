import 'package:flutter_riverpod/flutter_riverpod.dart';

// When `_refreshSilently` in events/cliques providers fails, it pushes the
// error here instead of overwriting the cached `AsyncData` with `AsyncError`
// (which would wipe the user-visible list). Home screen reads this to render
// an inline "Couldn't refresh — pull to retry" pill above the list.

final eventsRefreshErrorProvider = StateProvider<Object?>((ref) => null);
final cliquesRefreshErrorProvider = StateProvider<Object?>((ref) => null);
