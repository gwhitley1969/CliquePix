import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Check for API error envelope
    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['error'] != null && data['data'] == null) {
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
    }
    handler.next(response);
  }
}
