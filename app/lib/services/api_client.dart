import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';
import 'retry_interceptor.dart';

class ApiClient {
  late final Dio dio;

  ApiClient({required String baseUrl, required Ref ref}) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.addAll([
      AuthInterceptor(ref: ref),
      ErrorInterceptor(),
      RetryInterceptor(dio: dio),
    ]);
  }
}
