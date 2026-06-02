import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';

class AuthApi {
  final Dio dio;
  AuthApi(this.dio);

  Future<Map<String, dynamic>> verify() async {
    final response = await dio.post(ApiEndpoints.authVerify);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await dio.get(ApiEndpoints.usersMe);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> deleteAccount() async {
    await dio.delete(ApiEndpoints.usersMe);
  }

  /// POST /api/users/me/entitlement/refresh — backend re-syncs entitlement
  /// from RevenueCat's REST API and returns the enriched user.
  Future<Map<String, dynamic>> refreshEntitlement() async {
    final response = await dio.post(ApiEndpoints.usersMeEntitlementRefresh);
    return response.data['data'] as Map<String, dynamic>;
  }
}
