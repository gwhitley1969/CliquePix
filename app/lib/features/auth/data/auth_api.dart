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
}
