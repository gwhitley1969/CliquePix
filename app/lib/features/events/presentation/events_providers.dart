import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/event_model.dart';
import '../domain/events_repository.dart';
import '../data/events_api.dart';
import '../../../services/api_client.dart';

final eventsApiProvider = Provider<EventsApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EventsApi(apiClient.dio);
});

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.watch(eventsApiProvider));
});

final allEventsListProvider = AsyncNotifierProvider<AllEventsNotifier, List<EventModel>>(() {
  return AllEventsNotifier();
});

class AllEventsNotifier extends AsyncNotifier<List<EventModel>> {
  @override
  Future<List<EventModel>> build() async {
    final repo = ref.watch(eventsRepositoryProvider);
    return repo.listAllEvents();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(eventsRepositoryProvider).listAllEvents());
  }
}

final eventsListProvider = FutureProvider.family<List<EventModel>, String>((ref, circleId) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.listEvents(circleId);
});

final eventDetailProvider = FutureProvider.family<EventModel, String>((ref, eventId) async {
  final repo = ref.watch(eventsRepositoryProvider);
  return repo.getEvent(eventId);
});
