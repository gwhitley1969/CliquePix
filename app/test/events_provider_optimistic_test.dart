import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clique_pix/core/cache/last_refresh_error_provider.dart';
import 'package:clique_pix/core/cache/list_bootstrap_providers.dart';
import 'package:clique_pix/features/events/data/events_api.dart';
import 'package:clique_pix/features/events/domain/events_repository.dart';
import 'package:clique_pix/features/events/presentation/events_providers.dart';
import 'package:clique_pix/models/event_model.dart';

EventModel _event(String id) {
  final now = DateTime.utc(2026, 5, 3, 12);
  return EventModel(
    id: id,
    cliqueId: 'clique-1',
    name: 'Event $id',
    createdByUserId: 'creator-1',
    retentionHours: 168,
    status: 'active',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 168)),
  );
}

class _FakeRepo implements EventsRepository {
  _FakeRepo({this.shouldFail = false, List<EventModel>? freshList})
      : freshList = freshList ?? [_event('FRESH')];

  bool shouldFail;
  List<EventModel> freshList;
  int callCount = 0;

  @override
  Future<List<EventModel>> listAllEvents() async {
    callCount++;
    if (shouldFail) throw Exception('network blip');
    return freshList;
  }

  @override
  EventsApi get api => throw UnimplementedError();
  @override
  Future<EventModel> createEvent(
          String cliqueId, String name, String? description, int retentionHours) =>
      throw UnimplementedError();
  @override
  Future<List<EventModel>> listEvents(String cliqueId) =>
      throw UnimplementedError();
  @override
  Future<EventModel> getEvent(String eventId) => throw UnimplementedError();
  @override
  Future<void> deleteEvent(String eventId) => throw UnimplementedError();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bootstrap-seeded list yields AsyncData on first read', () async {
    final cached = [_event('CACHED-1'), _event('CACHED-2')];
    final repo = _FakeRepo();
    final container = ProviderContainer(overrides: [
      eventsBootstrapProvider.overrideWithValue(cached),
      eventsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final state = await container.read(allEventsListProvider.future);
    expect(state.map((e) => e.id), ['CACHED-1', 'CACHED-2']);
  });

  test('refresh failure preserves cached AsyncData (no AsyncError flip)',
      () async {
    final cached = [_event('CACHED')];
    final repo = _FakeRepo(shouldFail: true);
    final container = ProviderContainer(overrides: [
      eventsBootstrapProvider.overrideWithValue(cached),
      eventsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    // Initial read returns cached.
    await container.read(allEventsListProvider.future);

    // Wait for the microtask refresh to fire and fail.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final asyncState = container.read(allEventsListProvider);
    expect(asyncState.hasError, isFalse,
        reason: 'cached AsyncData must not be replaced with AsyncError');
    expect(asyncState.value!.map((e) => e.id), ['CACHED']);
    expect(container.read(eventsRefreshErrorProvider), isNotNull,
        reason: 'refresh error surfaces via separate provider');
  });

  test('successful refresh replaces cached list and clears error provider',
      () async {
    final cached = [_event('CACHED')];
    final repo = _FakeRepo(freshList: [_event('FRESH-1'), _event('FRESH-2')]);
    final container = ProviderContainer(overrides: [
      eventsBootstrapProvider.overrideWithValue(cached),
      eventsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    // Pre-set an error to ensure successful refresh clears it.
    container.read(eventsRefreshErrorProvider.notifier).state =
        Exception('prior error');

    await container.read(allEventsListProvider.future);

    // Wait for the microtask refresh to fire and succeed.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final asyncState = container.read(allEventsListProvider);
    expect(asyncState.value!.map((e) => e.id), ['FRESH-1', 'FRESH-2']);
    expect(container.read(eventsRefreshErrorProvider), isNull);
  });
}
