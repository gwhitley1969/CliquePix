import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(tokenStorageServiceProvider),
    ref.watch(telemetryServiceProvider),
  );
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final TokenStorageService _tokenStorage;
  final TelemetryService _telemetry;
  AppLifecycleService? _lifecycle;

  AuthNotifier(this._repository, this._tokenStorage, this._telemetry)
      : super(const AuthInitial()) {
    checkAuthStatus();
  }

  /// Try silent sign-in on app startup / resume (Layer 3).
  /// On failure, either route to Layer 5 re-login (if we have a last-known
  /// user and the failure looks like session expiry) or show the cold login
  /// screen (`AuthUnauthenticated`).
  Future<void> checkAuthStatus() async {
    state = const AuthLoading();
    try {
      final user = await _repository.silentSignIn();
      state = AuthAuthenticated(user);
      _startLifecycle();
    } catch (e) {
      await _handleSilentSignInFailure(e);
    }
  }

  Future<void> _handleSilentSignInFailure(Object error) async {
    final msg = error.toString();
    final isSessionExpired = msg.contains('AADSTS700082') ||
        msg.contains('AADSTS500210') ||
        msg.toLowerCase().contains('no current account') ||
        msg.toLowerCase().contains('no_account_found') ||
        msg.toLowerCase().contains('no account in the cache') ||
        msg.toLowerCase().contains('ui_required');

    final hint = await _tokenStorage.getLastKnownUser();
    if (isSessionExpired && hint.email != null && hint.email!.isNotEmpty) {
      debugPrint('[AUTH-LAYER-5] cold_start_relogin_required email=${hint.email}');
      _telemetry.record('cold_start_relogin_required');
      state = AuthReloginRequired(email: hint.email, displayName: hint.name);
    } else {
      state = const AuthUnauthenticated();
    }
  }

  /// Interactive sign-in via MSAL.
  /// [loginHint] supports the Layer 5 graceful re-login UX.
  Future<void> signIn({String? loginHint}) async {
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
      // MSAL errors (cache corruption, user cancel, session expired):
      // reset session and show clean login — not a persistent error loop.
      if (msg.contains('Msal') || msg.contains('AADSTS')) {
        await _repository.resetSession();
        state = const AuthUnauthenticated();
      } else {
        state = const AuthError('Sign in failed. Please try again.');
      }
    }
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
