import 'package:msal_flutter/msal_flutter.dart';
import '../../../models/user_model.dart';
import '../../../services/token_storage_service.dart';
import '../data/auth_api.dart';
import 'alarm_refresh_service.dart';
import 'background_token_service.dart';

class AuthRepository {
  final AuthApi api;
  final TokenStorageService tokenStorage;
  final AlarmRefreshService? alarmRefreshService;
  final BackgroundTokenService? backgroundTokenService;

  PublicClientApplication? _pca;

  static const _clientId = '7db01206-135b-4a34-a4d5-2622d1a888bf';
  static const _authority =
      'https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/';
  static const _scopes = <String>[
    'https://cliquepix.ciamlogin.com/$_clientId/.default',
  ];

  AuthRepository({
    required this.api,
    required this.tokenStorage,
    this.alarmRefreshService,
    this.backgroundTokenService,
  });

  Future<PublicClientApplication> _getOrCreatePca() async {
    _pca ??= await PublicClientApplication.createPublicClientApplication(
      _clientId,
      authority: _authority,
    );
    return _pca!;
  }

  /// Interactive sign-in — opens browser/webview for Entra login.
  /// [loginHint] is stored for Layer 5 graceful re-login UX but
  /// msal_flutter 2.x does not support passing it to acquireToken.
  Future<UserModel> signIn({String? loginHint}) async {
    final pca = await _getOrCreatePca();

    final accessToken = await pca.acquireToken(_scopes);

    // MSAL manages refresh tokens internally — we store the access token
    // and track lastRefreshTime for the proactive refresh logic.
    await tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: '',
    );

    final user = await verifyAndGetUser();

    // Schedule background refresh (Layers 2 & 4)
    await alarmRefreshService?.scheduleNextRefresh();
    await backgroundTokenService?.register();

    return user;
  }

  /// Silent token acquisition — uses MSAL's cached token/refresh token.
  Future<UserModel> silentSignIn() async {
    final pca = await _getOrCreatePca();

    final accessToken = await pca.acquireTokenSilent(_scopes);

    await tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: '',
    );

    final user = await verifyAndGetUser();

    // Reschedule background refresh
    await alarmRefreshService?.scheduleNextRefresh();

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
      await pca.logout();
    } catch (_) {
      // MSAL logout may fail if no active session — continue cleanup
    }
    await alarmRefreshService?.cancelRefresh();
    await backgroundTokenService?.cancel();
    await tokenStorage.clearAll();
  }

  /// Attempt silent token refresh via MSAL.
  /// Returns true on success, false on failure.
  Future<bool> refreshToken() async {
    try {
      final pca = await _getOrCreatePca();
      final accessToken = await pca.acquireTokenSilent(_scopes);
      await tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: '',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
