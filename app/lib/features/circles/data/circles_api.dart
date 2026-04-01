import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class CirclesApi {
  final Dio dio;
  CirclesApi(this.dio);

  Future<Map<String, dynamic>> createCircle(String name) async {
    final response = await dio.post(ApiEndpoints.circles, data: {'name': name});
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listCircles() async {
    final response = await dio.get(ApiEndpoints.circles);
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getCircle(String circleId) async {
    final response = await dio.get(ApiEndpoints.circle(circleId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getInviteInfo(String circleId) async {
    final response = await dio.post(ApiEndpoints.circleInvite(circleId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinCircle(String circleId, String inviteCode) async {
    final response = await dio.post(
      ApiEndpoints.circleJoin(circleId),
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinByInviteCode(String inviteCode) async {
    // The join endpoint accepts invite_code in body; circleId is resolved server-side
    final response = await dio.post(
      '/api/circles/_/join',
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listMembers(String circleId) async {
    final response = await dio.get(ApiEndpoints.circleMembers(circleId));
    return response.data['data'] as List<dynamic>;
  }

  Future<void> leaveCircle(String circleId) async {
    await dio.delete(ApiEndpoints.circleLeave(circleId));
  }

  Future<void> removeMember(String circleId, String userId) async {
    await dio.delete(ApiEndpoints.circleMember(circleId, userId));
  }
}
