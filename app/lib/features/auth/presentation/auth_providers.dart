import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/auth_state.dart';
import '../domain/auth_repository.dart';
import '../data/auth_api.dart';
import '../../../services/api_client.dart';
import '../../../services/token_storage_service.dart';

final authApiProvider = Provider<AuthApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthApi(apiClient.dio);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepository(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageServiceProvider),
  );
  // Wire the token refresh callback so the auth interceptor can trigger
  // MSAL silent acquisition when the stored access token expires.
  ref.watch(tokenStorageServiceProvider).setRefreshCallback(repo.refreshToken);
  return repo;
});

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AuthInitial()) {
    checkAuthStatus();
  }

  /// Try silent sign-in on app startup / resume (Layer 3).
  /// On failure, sets AuthUnauthenticated (clean login) — never AuthError.
  Future<void> checkAuthStatus() async {
    state = const AuthLoading();
    try {
      final user = await _repository.silentSignIn();
      state = AuthAuthenticated(user);
    } catch (_) {
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
    } catch (e) {
      final msg = e.toString();
      // MSAL errors (cache corruption, user cancel, session expired):
      // reset session and show clean login — not a persistent error loop.
      if (msg.contains('Msal') || msg.contains('AADSTS')) {
        await _repository.resetSession();
        state = const AuthUnauthenticated();
      } else {
        state = AuthError('Sign in failed. Please try again.');
      }
    }
  }

  void clearError() => state = const AuthUnauthenticated();

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthUnauthenticated();
  }
}
