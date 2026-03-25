import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['error'] != null && data['data'] == null) {
        final error = data['error'] as Map<String, dynamic>;
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            message: error['message'] as String? ?? 'Unknown API error',
          ),
        );
        return;
      }
    }
    handler.next(response);
  }
}
