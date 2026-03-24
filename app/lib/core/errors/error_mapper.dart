import 'package:dio/dio.dart';
import 'app_failures.dart';

class ErrorMapper {
  ErrorMapper._();

  static AppFailure fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badResponse:
        return _fromStatusCode(e.response?.statusCode, e.response?.data);
      case DioExceptionType.cancel:
        return const NetworkFailure('Request cancelled.');
      default:
        return const ServerFailure();
    }
  }

  static AppFailure _fromStatusCode(int? statusCode, dynamic data) {
    final message = _extractErrorMessage(data);

    switch (statusCode) {
      case 401:
        return AuthFailure(message ?? 'Authentication required.');
      case 403:
        return PermissionFailure(message ?? 'Permission denied.');
      case 404:
        return NotFoundFailure(message ?? 'Not found.');
      case 409:
        return ValidationFailure(message ?? 'Conflict.');
      case 422:
        return ValidationFailure(message ?? 'Invalid input.');
      case >= 500:
        return ServerFailure(message ?? 'Server error.');
      default:
        return ServerFailure(message ?? 'An unexpected error occurred.');
    }
  }

  static String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        return error['message'] as String?;
      }
    }
    return null;
  }
}
