import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_model.dart';
import '../../../services/api_client.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/token_storage_service.dart';
import '../data/auth_api.dart';
import '../domain/app_lifecycle_service.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/background_token_service.dart';

final authApiProvider = Provider<AuthApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthApi(apiClient.dio);
});

final backgroundTokenServiceProvider =
    Provider<BackgroundTokenService>((_) => BackgroundTokenService());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepository(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageServiceProvider),
    backgroundTokenService: ref.watch(backgroundTokenServiceProvider),
  );
  // Wire the token refresh callback so the auth interceptor can trigger
  // MSAL silent acquisition when the stored access token expires.
  ref.watch(tokenStorageServiceProvider).setRefreshCallback(repo.refreshToken);
  return repo;
});

/// Optimistic bootstrap state computed from storage in `main()` before
/// `runApp`. Overridden in the `ProviderScope` at app start; reading this
/// without an override throws — it is never meant to be used unseeded.
///
/// If storage contains both an access token and a cached `UserModel`, the
/// override emits `AuthAuthenticated(cachedUser)` — the UI renders the
/// signed-in experience immediately, and `AuthNotifier` kicks off
/// background verification. If storage is empty, the override emits
/// `AuthUnauthenticated` — the LoginScreen renders with an enabled
/// Get Started button on the first frame.
final authBootstrapStateProvider = Provider<AuthState>((_) {
  throw StateError(
    'authBootstrapStateProvider must be overridden in main() before runApp',
  );
});

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(tokenStorageServiceProvider),
    ref.watch(telemetryServiceProvider),
    bootstrap: ref.watch(authBootstrapStateProvider),
  );
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final TokenStorageService _tokenStorage;
  final TelemetryService _telemetry;
  AppLifecycleService? _lifecycle;

  bool _signingIn = false;
  bool _verifying = false;

  AuthNotifier(
    this._repository,
    this._tokenStorage,
    this._telemetry, {
    required AuthState bootstrap,
  }) : super(bootstrap) {
    // Optimistic bootstrap: if we seeded AuthAuthenticated from cached
    // storage, start the Layer-3 lifecycle observer and fire background
    // verification so the cached user is replaced with the authoritative
    // server record (and a stale/expired session is surfaced as a graceful
    // re-login prompt, not an indefinite hang).
    if (bootstrap is AuthAuthenticated) {
      _startLifecycle();
      // Fire-and-forget — must not block constructor resolution.
      unawaited(_verifyInBackground());
    }
  }

  /// Background verification of the cached session. Runs concurrently with
  /// the user's first interactions — never blocks the UI.
  ///
  /// On success: replace the provisional cached user with the server's
  /// authoritative record (also refreshes the stored token via silentSignIn).
  ///
  /// On failure with a session-expired signature (AADSTS700082, AADSTS500210,
  /// no_account_found, or timeout with a cached email): transition to
  /// `AuthReloginRequired`. The GoRouter redirect then bounces the user from
  /// `/events` back to `/login`, where `LoginScreen` pops the
  /// `WelcomeBackDialog` for one-tap re-auth.
  ///
  /// On other failures (network hiccup without session expiry): leave the
  /// optimistic `AuthAuthenticated` in place — the next Layer-3 resume or
  /// AuthInterceptor 401 will retry.
  Future<void> _verifyInBackground() async {
    if (_verifying) return;
    _verifying = true;
    _telemetry.record('background_verification_started');
    try {
      final user = await _repository
          .silentSignIn()
          .timeout(const Duration(seconds: 8));
      state = AuthAuthenticated(user);
      _telemetry.record('background_verification_success');
    } on TimeoutException {
      _telemetry.record('background_verification_timeout');
      await _handleSilentSignInFailure(Exception('silent_signin_timeout'));
    } catch (e) {
      await _handleSilentSignInFailure(e);
    } finally {
      _verifying = false;
    }
  }

  Future<void> _handleSilentSignInFailure(Object error) async {
    final msg = error.toString();
    final isSessionExpired = msg.contains('AADSTS700082') ||
        msg.contains('AADSTS500210') ||
        msg.contains('silent_signin_timeout') ||
        msg.toLowerCase().contains('no current account') ||
        msg.toLowerCase().contains('no_account_found') ||
        msg.toLowerCase().contains('no account in the cache') ||
        msg.toLowerCase().contains('ui_required');

    final hint = await _tokenStorage.getLastKnownUser();
    if (isSessionExpired && hint.email != null && hint.email!.isNotEmpty) {
      debugPrint('[AUTH-LAYER-5] cold_start_relogin_required email=${hint.email}');
      _telemetry.record('cold_start_relogin_required');
      _stopLifecycle();
      state = AuthReloginRequired(email: hint.email, displayName: hint.name);
    } else if (state is AuthAuthenticated && !isSessionExpired) {
      // Non-session failure (transient network, etc.) — keep optimistic
      // state; next resume or 401 will retry. Do not strand the user.
      debugPrint(
          '[AUTH-BG-VERIFY] transient failure, keeping optimistic auth: $msg');
    } else {
      _stopLifecycle();
      state = const AuthUnauthenticated();
    }
  }

  /// Interactive sign-in via MSAL.
  /// [loginHint] supports the Layer 5 graceful re-login UX.
  Future<void> signIn({String? loginHint}) async {
    if (_signingIn) {
      debugPrint('[AUTH] signIn: already in progress, ignoring duplicate tap');
      return;
    }
    _signingIn = true;
    state = const AuthLoading();
    try {
      final user = await _repository.signIn(loginHint: loginHint);
      state = AuthAuthenticated(user);
      _startLifecycle();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        final err = e.response?.data is Map<String, dynamic>
            ? e.response!.data['error'] as Map<String, dynamic>?
            : null;
        if (err?['code'] == 'AGE_VERIFICATION_FAILED') {
          await _repository.resetSession();
          final serverMessage = err?['message'] as String?;
          state = AuthError(
            serverMessage ?? 'You must be at least 13 years old to use Clique Pix.',
          );
          return;
        }
      }

      final msg = e.toString();
      // MSAL errors (cache corruption, user cancel, session expired) and
      // backend-unreachable timeouts: reset session and show clean login —
      // not a persistent error loop.
      if (msg.contains('Msal') || msg.contains('AADSTS')) {
        await _repository.resetSession();
        state = const AuthUnauthenticated();
      } else if (e is TimeoutException) {
        state = const AuthError('Sign in timed out. Please try again.');
      } else {
        state = const AuthError('Sign in failed. Please try again.');
      }
    } finally {
      _signingIn = false;
    }
  }

  /// Escape-hatch entry point from LoginScreen after the user has stared at
  /// a hung spinner for 15+ seconds. Clears MSAL cache and stored tokens,
  /// then starts a fresh interactive sign-in.
  Future<void> resetAndSignIn() async {
    _telemetry.record('login_screen_escape_hatch_tapped');
    await _repository.resetSession();
    _stopLifecycle();
    state = const AuthUnauthenticated();
    await signIn();
  }

  void clearError() => state = const AuthUnauthenticated();

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } finally {
      _stopLifecycle();
      state = const AuthUnauthenticated();
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _repository.deleteAccount();
    } finally {
      _stopLifecycle();
      state = const AuthUnauthenticated();
    }
  }

  /// Swap in a refreshed [UserModel] after an avatar upload / remove /
  /// frame change / prompt action. Pure in-memory state mutation — does
  /// NOT trigger a token refresh (the 5-layer defense must not see
  /// spurious refresh calls from avatar paths). Callers are every avatar
  /// endpoint consumer: `AvatarEditorScreen`, the welcome-prompt handler,
  /// and the delete/frame paths.
  void updateUserAvatar(UserModel updated) {
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(updated);
    }
  }

  /// Entry into Layer 5. Called when Layer 3 detects that the foreground
  /// refresh failed. Reads last-known-user and emits AuthReloginRequired;
  /// LoginScreen renders WelcomeBackDialog in response.
  Future<void> _triggerWelcomeBack() async {
    final hint = await _tokenStorage.getLastKnownUser();
    debugPrint('[AUTH-LAYER-5] welcome_back_shown email=${hint.email}');
    _telemetry.record('welcome_back_shown');
    _stopLifecycle();
    state = AuthReloginRequired(email: hint.email, displayName: hint.name);
  }

  void _startLifecycle() {
    _lifecycle?.stop();
    _lifecycle = AppLifecycleService(
      tokenStorage: _tokenStorage,
      refreshCallback: _repository.refreshToken,
      reloginCallback: _triggerWelcomeBack,
      telemetry: (event, {errorCode, extra}) =>
          _telemetry.record(event, errorCode: errorCode, extra: extra),
    );
    _lifecycle!.start();
  }

  void _stopLifecycle() {
    _lifecycle?.stop();
    _lifecycle = null;
  }

  @override
  void dispose() {
    _stopLifecycle();
    super.dispose();
  }
}
