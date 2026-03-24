import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'token_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final Ref ref;

  AuthInterceptor({required this.ref});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final tokenStorage = ref.read(tokenStorageServiceProvider);
    final accessToken = await tokenStorage.getAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Attempt silent token refresh
      try {
        final tokenStorage = ref.read(tokenStorageServiceProvider);
        final refreshed = await tokenStorage.refreshToken();
        if (refreshed) {
          // Retry the original request
          final accessToken = await tokenStorage.getAccessToken();
          err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
          final response = await Dio().fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (_) {
        // Refresh failed, propagate original error
      }
    }
    handler.next(err);
  }
}
