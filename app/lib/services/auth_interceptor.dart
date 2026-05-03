import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/auth_providers.dart';
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
        // Use refreshTokenDetailed (returns RefreshResult with errorCode)
        // instead of the bool refreshToken so we can distinguish a recoverable
        // refresh failure from a session-expired one. On session-expired
        // (AADSTS700082 inactivity-timeout, AADSTS500210 federated, or
        // no-cached-account), signal AuthNotifier so it transitions to
        // AuthReloginRequired immediately — racing the AsyncError that the
        // 401 would otherwise produce on whichever screen made the call.
        // Without this hook, the user briefly saw the raw DioException UI on
        // home_screen before the parallel `_verifyInBackground` finished and
        // routed them to WelcomeBackDialog. See `welcome_back_shown` events
        // with `source=interceptor` to measure how often this fires.
        final repo = ref.read(authRepositoryProvider);
        final result = await repo
            .refreshTokenDetailed()
            .timeout(const Duration(seconds: 8));
        if (result.success) {
          final tokenStorage = ref.read(tokenStorageServiceProvider);
          final accessToken = await tokenStorage.getAccessToken();
          err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
          final response = await dio.fetch(err.requestOptions);
          return handler.resolve(response);
        }
        if (_isSessionExpired(result.errorCode)) {
          // Fire-and-forget so this never blocks the error propagation. The
          // notifier guards against double-firing.
          unawaited(ref
              .read(authStateProvider.notifier)
              .triggerWelcomeBackOnSessionExpiry(reason: result.errorCode));
        }
      } on TimeoutException {
        // Refresh hung — propagate original 401 so the caller handles it.
        // Do not signal welcome-back: a hung refresh is more likely a network
        // hiccup than a session-expiry, and the next Layer-3 resume will retry
        // cleanly. Signaling welcome-back here would log the user out on a
        // transient timeout.
      } catch (_) {
        // Refresh failed unexpectedly (DI not ready, provider error, etc.) —
        // propagate original 401.
      }
    }
    handler.next(err);
  }

  /// Matches the same session-expired patterns that
  /// `AuthRepository._extractAadstsCode` emits and that
  /// `AuthNotifier._handleSilentSignInFailure` checks for. Keep these three
  /// matchers in sync — adding a new pattern (e.g., a future Entra error code)
  /// requires updating all three places.
  static bool _isSessionExpired(String? errorCode) {
    if (errorCode == null) return false;
    return errorCode == 'AADSTS700082' ||
        errorCode == 'AADSTS500210' ||
        errorCode == 'no_account_found';
  }
}
