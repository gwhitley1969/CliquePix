import 'package:msal_auth/msal_auth.dart';
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

  SingleAccountPca? _pca;

  static const _clientId = '7db01206-135b-4a34-a4d5-2622d1a888bf';
  static const _authority =
      'https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/';
  static const _scopes = <String>[
    'api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user',
  ];

  AuthRepository({
    required this.api,
    required this.tokenStorage,
    this.alarmRefreshService,
    this.backgroundTokenService,
  });

  Future<SingleAccountPca> _getOrCreatePca() async {
    _pca ??= await SingleAccountPca.create(
      clientId: _clientId,
      androidConfig: AndroidConfig(
        configFilePath: 'assets/msal_config.json',
        redirectUri: 'msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D',
      ),
      appleConfig: AppleConfig(
        authority: _authority,
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
      scopes: _scopes,
      loginHint: loginHint,
    );

    // MSAL manages refresh tokens internally — we store the access token
    // and track lastRefreshTime for the proactive refresh logic.
    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
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

    final result = await pca.acquireTokenSilent(scopes: _scopes);

    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
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
      await pca.signOut();
    } catch (_) {
      // MSAL sign out may fail if no active session — continue cleanup
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
      final result = await pca.acquireTokenSilent(scopes: _scopes);
      await tokenStorage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: '',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
