import 'dart:math';
import 'package:dio/dio.dart';

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final isRetryable = statusCode == null ||
        statusCode >= 500 ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;

    if (!isRetryable) {
      handler.next(err);
      return;
    }

    final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;
    if (retryCount >= maxRetries) {
      handler.next(err);
      return;
    }

    // Exponential backoff
    final delay = Duration(milliseconds: pow(2, retryCount).toInt() * 500);
    await Future.delayed(delay);

    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
