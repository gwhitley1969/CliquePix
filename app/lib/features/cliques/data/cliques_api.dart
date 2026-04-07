import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class CliquesApi {
  final Dio dio;
  CliquesApi(this.dio);

  Future<Map<String, dynamic>> createClique(String name) async {
    final response = await dio.post(ApiEndpoints.cliques, data: {'name': name});
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listCliques() async {
    final response = await dio.get(ApiEndpoints.cliques);
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getClique(String cliqueId) async {
    final response = await dio.get(ApiEndpoints.clique(cliqueId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getInviteInfo(String cliqueId) async {
    final response = await dio.post(ApiEndpoints.cliqueInvite(cliqueId));
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinClique(String cliqueId, String inviteCode) async {
    final response = await dio.post(
      ApiEndpoints.cliqueJoin(cliqueId),
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinByInviteCode(String inviteCode) async {
    // The join endpoint accepts invite_code in body; cliqueId is resolved server-side
    final response = await dio.post(
      '/api/cliques/_/join',
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listMembers(String cliqueId) async {
    final response = await dio.get(ApiEndpoints.cliqueMembers(cliqueId));
    return response.data['data'] as List<dynamic>;
  }

  Future<void> leaveClique(String cliqueId) async {
    await dio.delete(ApiEndpoints.cliqueLeave(cliqueId));
  }

  Future<void> removeMember(String cliqueId, String userId) async {
    await dio.delete(ApiEndpoints.cliqueMember(cliqueId, userId));
  }
}
