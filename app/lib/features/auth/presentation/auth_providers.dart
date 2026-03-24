import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/auth_state.dart';
import '../domain/auth_repository.dart';
import '../data/auth_api.dart';
import '../../../services/token_storage_service.dart';

final authApiProvider = Provider<AuthApi>((ref) {
  // TODO: Wire up with actual Dio instance from ApiClient
  throw UnimplementedError('Wire up AuthApi with Dio');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageServiceProvider),
  );
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AuthInitial());

  Future<void> checkAuthStatus() async {
    state = const AuthLoading();
    try {
      final user = await _repository.silentSignIn();
      state = AuthAuthenticated(user);
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> signIn() async {
    state = const AuthLoading();
    try {
      final user = await _repository.signIn();
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthUnauthenticated();
  }
}
