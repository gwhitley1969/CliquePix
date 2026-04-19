import 'package:flutter/foundation.dart';
import 'package:msal_auth/msal_auth.dart';
import '../../../core/constants/msal_constants.dart';
import '../../../models/user_model.dart';
import '../../../services/token_storage_service.dart';
import '../data/auth_api.dart';
import 'background_token_service.dart';

/// Result of a silent token refresh attempt, including the MSAL error code
/// (if any) so callers — notably `AppLifecycleService` and the cold-start
/// path in `AuthNotifier.checkAuthStatus` — can distinguish:
///   - `AADSTS700082` — refresh token expired due to inactivity (Entra bug)
///   - `AADSTS500210` — iOS #2871 federated-user silent refresh failure
///   - `no_account_found` / `no_current_account` — nothing in MSAL cache
///   - null errorCode with success=true — refreshed successfully
class RefreshResult {
  final bool success;
  final String? errorCode;
  const RefreshResult({required this.success, this.errorCode});
}

class AuthRepository {
  final AuthApi api;
  final TokenStorageService tokenStorage;
  final BackgroundTokenService backgroundTokenService;

  SingleAccountPca? _pca;

  AuthRepository({
    required this.api,
    required this.tokenStorage,
    required this.backgroundTokenService,
  });

  Future<SingleAccountPca> _getOrCreatePca() async {
    _pca ??= await SingleAccountPca.create(
      clientId: MsalConstants.clientId,
      androidConfig: AndroidConfig(
        configFilePath: MsalConstants.androidConfigFilePath,
        redirectUri: MsalConstants.androidRedirectUri,
      ),
      appleConfig: AppleConfig(
        authority: MsalConstants.authority,
        authorityType: AuthorityType.b2c,
        broker: Broker.safariBrowser,
      ),
    );
    return _pca!;
  }

  /// Interactive sign-in — opens browser/webview for Entra login.
  /// [loginHint] pre-fills the user's email for Layer 5 graceful re-login UX.
  Future<UserModel> signIn({String? loginHint}) async {
    final pca = await _getOrCreatePca();

    final result = await pca.acquireToken(
      scopes: MsalConstants.scopes,
      prompt: Prompt.login,
      loginHint: loginHint,
    );

    // MSAL manages refresh tokens internally — we store the access token
    // and track lastRefreshTime for the proactive refresh logic.
    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: '',
    );

    final user = await verifyAndGetUser();

    // Layer 4: schedule WorkManager background refresh (best-effort backup)
    await backgroundTokenService.register();

    return user;
  }

  /// Silent token acquisition — uses MSAL's cached token/refresh token.
  Future<UserModel> silentSignIn() async {
    final pca = await _getOrCreatePca();

    final result = await pca.acquireTokenSilent(scopes: MsalConstants.scopes);

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: '',
    );

    final user = await verifyAndGetUser();
    return user;
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
    try {
      final pca = await _getOrCreatePca();
      await pca.signOut();
    } catch (_) {
      // MSAL sign out may fail if no active session — continue cleanup
    }
    _pca = null; // Force fresh PCA on next sign-in
    try { await backgroundTokenService.cancel(); } catch (_) {}
    try { await tokenStorage.clearAll(); } catch (_) {}
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    try {
      final pca = await _getOrCreatePca();
      await pca.signOut();
    } catch (_) {}
    _pca = null;
    try { await backgroundTokenService.cancel(); } catch (_) {}
    try { await tokenStorage.clearAll(); } catch (_) {}
  }

  /// Clear MSAL cached account and force fresh PCA on next attempt.
  /// Used to recover from corrupted/stale MSAL sessions.
  Future<void> resetSession() async {
    try {
      final pca = await _getOrCreatePca();
      await pca.signOut();
    } catch (_) {}
    _pca = null;
    await tokenStorage.clearAll();
  }

  /// Attempt silent token refresh via MSAL. Returns true on success, false
  /// on failure. Prefer `refreshTokenDetailed()` if you need the error code.
  Future<bool> refreshToken() async {
    final r = await refreshTokenDetailed();
    return r.success;
  }

  /// Silent refresh that surfaces the MSAL error code for Layer-5 routing.
  Future<RefreshResult> refreshTokenDetailed() async {
    try {
      final pca = await _getOrCreatePca();
      final result = await pca.acquireTokenSilent(scopes: MsalConstants.scopes);
      await tokenStorage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: '',
      );
      debugPrint('[AUTH-REFRESH] success');
      return const RefreshResult(success: true);
    } catch (e) {
      final errorCode = _extractAadstsCode(e.toString());
      debugPrint('[AUTH-REFRESH] failed code=$errorCode msg=${e.toString().split("\n").first}');
      return RefreshResult(success: false, errorCode: errorCode);
    }
  }

  /// Extracts the `AADSTSxxxxxx` code from an MSAL exception message. Returns
  /// a synthetic `no_account_found` if the message indicates the MSAL cache
  /// is empty (seen as `IllegalArgumentException` / `MsalUiRequiredException`
  /// depending on platform). Returns `unknown` if no code parses out.
  String _extractAadstsCode(String message) {
    final match = RegExp(r'AADSTS\d{5,6}').firstMatch(message);
    if (match != null) return match.group(0)!;
    final lower = message.toLowerCase();
    if (lower.contains('no current account') ||
        lower.contains('no_account_found') ||
        lower.contains('no_tokens_found') ||
        lower.contains('no account in the cache') ||
        lower.contains('ui_required')) {
      return 'no_account_found';
    }
    return 'unknown';
  }
}
