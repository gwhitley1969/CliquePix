import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_model.dart';
import '../../../services/token_storage_service.dart';
import '../data/auth_api.dart';
import 'alarm_refresh_service.dart';
import 'background_token_service.dart';

class AuthRepository {
  final AuthApi api;
  final TokenStorageService tokenStorage;

  AuthRepository({required this.api, required this.tokenStorage});

  Future<UserModel> signIn() async {
    // TODO: Implement MSAL sign-in flow with cliquepix.onmicrosoft.com
    // 1. Call MSAL interactive login
    // 2. Get access token + refresh token
    // 3. Save tokens via tokenStorage.saveTokens()
    // 4. Call api.verify() to upsert user
    // 5. Return UserModel
    throw UnimplementedError('MSAL integration pending');
  }

  Future<UserModel> silentSignIn() async {
    // Try silent token acquisition via MSAL
    // If successful, call api.verify()
    throw UnimplementedError('MSAL integration pending');
  }

  Future<UserModel> verifyAndGetUser() async {
    final data = await api.verify();
    final user = UserModel.fromJson(data);
    await tokenStorage.saveLastKnownUser(user.emailOrPhone, user.displayName);
    return user;
  }

  Future<UserModel> getMe() async {
    final data = await api.getMe();
    return UserModel.fromJson(data);
  }

  Future<void> signOut() async {
    await AlarmRefreshService.cancelRefresh();
    await BackgroundTokenService.cancel();
    await tokenStorage.clearAll();
  }

  Future<bool> refreshToken() async {
    try {
      // TODO: MSAL silent token acquisition
      // await tokenStorage.saveTokens(accessToken: newToken, refreshToken: newRefresh);
      return false;
    } catch (_) {
      return false;
    }
  }
}
