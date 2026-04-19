import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'token_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final Ref ref;
  final Dio dio;

  AuthInterceptor({required this.ref, required this.dio});

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
      try {
        final tokenStorage = ref.read(tokenStorageServiceProvider);
        // Bound the refresh so a hung MSAL call cannot freeze every
        // subsequent API request behind this interceptor.
        final refreshed = await tokenStorage
            .refreshToken()
            .timeout(const Duration(seconds: 8));
        if (refreshed) {
          final accessToken = await tokenStorage.getAccessToken();
          err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
          final response = await dio.fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } on TimeoutException {
        // Refresh hung — propagate original 401 so the caller handles it.
      } catch (_) {
        // Refresh failed, propagate original error.
      }
    }
    handler.next(err);
  }
}
