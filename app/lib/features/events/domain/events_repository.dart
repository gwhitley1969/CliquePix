import '../../../models/event_model.dart';
import '../data/events_api.dart';

class EventsRepository {
  final EventsApi api;
  EventsRepository(this.api);

  Future<EventModel> createEvent(String cliqueId, String name, String? description, int retentionHours) async {
    final data = await api.createEvent(cliqueId, name, description, retentionHours);
    return EventModel.fromJson(data);
  }

  Future<List<EventModel>> listAllEvents() async {
    final data = await api.listAllEvents();
    return data.map((e) => EventModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<EventModel>> listEvents(String cliqueId) async {
    final data = await api.listEvents(cliqueId);
    return data.map((e) => EventModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<EventModel> getEvent(String eventId) async {
    final data = await api.getEvent(eventId);
    return EventModel.fromJson(data);
  }

  Future<void> deleteEvent(String eventId) async {
    await api.deleteEvent(eventId);
  }
}
