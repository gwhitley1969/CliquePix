import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class EventsApi {
  final Dio dio;
  EventsApi(this.dio);

  Future<Map<String, dynamic>> createEvent(String circleId, String name, String? description, int retentionHours) async {
    final response = await dio.post(
      ApiEndpoints.circleEvents(circleId),
      data: {
        'name': name,
        'description': description,
        'retention_hours': retentionHours,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listAllEvents() async {
    final response = await dio.get(ApiEndpoints.events);
    return response.data['data'] as List<dynamic>;
  }

  Future<List<dynamic>> listEvents(String circleId) async {
    final response = await dio.get(ApiEndpoints.circleEvents(circleId));
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getEvent(String eventId) async {
    final response = await dio.get(ApiEndpoints.event(eventId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> deleteEvent(String eventId) async {
    await dio.delete(ApiEndpoints.event(eventId));
  }
}
