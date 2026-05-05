import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_model.dart';
import '../../../services/api_client.dart';
import '../../../services/friday_reminder_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/token_storage_service.dart';
import '../../dm/domain/dm_realtime_service.dart';
import '../../dm/domain/dm_repository.dart';
import '../../dm/presentation/dm_providers.dart';
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
    ref.watch(dmRealtimeServiceProvider),
    ref.watch(dmRepositoryProvider),
    bootstrap: ref.watch(authBootstrapStateProvider),
  );
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final TokenStorageService _tokenStorage;
  final TelemetryService _telemetry;
  final DmRealtimeService _realtime;
  final DmRepository _dmRepo;
  AppLifecycleService? _lifecycle;

  bool _signingIn = false;
  bool _verifying = false;

  AuthNotifier(
    this._repository,
    this._tokenStorage,
    this._telemetry,
    this._realtime,
    this._dmRepo, {
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
    } catch (e, st) {
      debugPrint('[AUTH-SIGNIN-FAIL] type=${e.runtimeType} msg=$e');
      if (e is DioException) {
        debugPrint(
            '[AUTH-SIGNIN-FAIL] dio.type=${e.type} dio.status=${e.response?.statusCode} dio.body=${e.response?.data}');
      } else {
        debugPrint('[AUTH-SIGNIN-FAIL] stack=${st.toString().split("\n").take(8).join(" | ")}');
      }
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
  /// refresh failed, OR when the AuthInterceptor catches a 401 whose token
  /// refresh failed with a session-expired signature
  /// (`triggerWelcomeBackOnSessionExpiry`). Reads last-known-user and emits
  /// AuthReloginRequired; LoginScreen renders WelcomeBackDialog in response.
  ///
  /// [source] / [reason] are recorded as telemetry dimensions so we can split
  /// the welcome-back funnel by trigger origin (`lifecycle` from Layer 3,
  /// `interceptor` from a 401 in flight). Useful for measuring whether the
  /// interceptor coordination eliminates the AsyncError-then-WelcomeBack
  /// flicker we shipped this fix to address.
  Future<void> _triggerWelcomeBack({String? source, String? reason}) async {
    final hint = await _tokenStorage.getLastKnownUser();
    debugPrint('[AUTH-LAYER-5] welcome_back_shown email=${hint.email} '
               'source=${source ?? "lifecycle"} reason=${reason ?? "-"}');
    final extra = <String, String>{};
    if (source != null) extra['source'] = source;
    if (reason != null) extra['reason'] = reason;
    _telemetry.record('welcome_back_shown',
        extra: extra.isEmpty ? null : extra);
    _stopLifecycle();
    state = AuthReloginRequired(email: hint.email, displayName: hint.name);
  }

  /// Public entry into Layer 5 from the AuthInterceptor when a 401's token
  /// refresh fails with a session-expired pattern (AADSTS700082 etc).
  /// Guards against double-firing — no-op if state is already in a terminal
  /// re-login or unauth path, or actively signing in. Always fire-and-forget
  /// from the interceptor so the original 401 still propagates to the caller
  /// (which surfaces as AsyncError on whichever screen made the call); the
  /// state transition this method drives causes GoRouter to redirect to
  /// /login + LoginScreen pops WelcomeBackDialog, replacing the AsyncError UI.
  Future<void> triggerWelcomeBackOnSessionExpiry({String? reason}) async {
    final current = state;
    if (current is AuthReloginRequired ||
        current is AuthUnauthenticated ||
        current is AuthLoading) {
      return;
    }
    await _triggerWelcomeBack(source: 'interceptor', reason: reason);
  }

  void _telemetryRecord(String event,
      {String? errorCode, Map<String, String>? extra}) {
    _telemetry.record(event, errorCode: errorCode, extra: extra);
  }

  void _startLifecycle() {
    _lifecycle?.stop();
    _lifecycle = AppLifecycleService(
      tokenStorage: _tokenStorage,
      refreshCallback: _repository.refreshToken,
      reloginCallback: _triggerWelcomeBack,
      telemetry: _telemetryRecord,
      onResumed: _onAppResumedTasks,
    );
    _lifecycle!.start();

    // Defer the unawaited side effects by one frame so they don't pile onto
    // the same UI tick as the auth-state rebuild + GoRouter redirect +
    // HomeScreen first build. On iOS first sign-in this matters because the
    // FlutterViewController is also re-attaching from SFSafariViewController.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initial schedule for users who never resume (cold-start sign-in,
      // immediate use). Idempotent — the resume hook reuses the same path.
      unawaited(
        FridayReminderService.scheduleOrReschedule(
                telemetry: _telemetryRecord)
            .catchError((Object e) {
          debugPrint('[AUTH] Friday reminder schedule failed: $e');
        }),
      );
      // Initial realtime connect — gives the user instant fan-out for
      // `new_event`, `video_ready`, and DM messages regardless of which
      // screen they're on.
      unawaited(_connectRealtime());
    });
  }

  /// Auth-independent tasks that must run on every `AppLifecycleState.resumed`.
  /// Future.wait runs them in parallel so a failure in one cannot prevent
  /// the others from executing. Per-task `catchError` keeps an exception
  /// from propagating up and breaking the sibling tasks.
  Future<void> _onAppResumedTasks() async {
    await Future.wait([
      FridayReminderService.scheduleOrReschedule(telemetry: _telemetryRecord)
          .catchError((Object e) {
        debugPrint('[AUTH] Friday reminder reschedule on resume failed: $e');
      }),
      _reconnectRealtimeIfDropped().catchError((Object e) {
        debugPrint('[AUTH] Realtime reconnect on resume failed: $e');
      }),
    ]);
  }

  /// 3-step Web PubSub connect dance:
  ///   (1) Wire onNegotiate so the service can renew its WebSocket URL on
  ///       token expiry without a sign-out (Web PubSub access tokens TTL ~60min).
  ///   (2) Idempotent — short-circuit if already connected.
  ///   (3) Negotiate fresh URL + connect.
  Future<void> _connectRealtime() async {
    try {
      _realtime.onNegotiate = () => _dmRepo.negotiate();
      if (_realtime.isConnected) return;
      final url = await _dmRepo.negotiate();
      await _realtime.connect(url);
      _telemetryRecord('realtime_connected', extra: {'reason': 'auth_start'});
    } catch (e) {
      _telemetryRecord('realtime_connect_failed',
          errorCode: e.toString().split('\n').first);
      debugPrint('[AUTH] Realtime connect failed: $e');
    }
  }

  /// Resume-hook reconnect: no-op if the WebSocket is still alive; otherwise
  /// re-runs the connect dance and emits `realtime_reconnected_on_resume`
  /// telemetry so we can trace how often the connection was dropped.
  Future<void> _reconnectRealtimeIfDropped() async {
    if (_realtime.isConnected) return;
    try {
      _realtime.onNegotiate = () => _dmRepo.negotiate();
      final url = await _dmRepo.negotiate();
      await _realtime.connect(url);
      _telemetryRecord('realtime_connected',
          extra: {'reason': 'reconnect_on_resume'});
      _telemetryRecord('realtime_reconnected_on_resume');
    } catch (e) {
      _telemetryRecord('realtime_connect_failed',
          errorCode: e.toString().split('\n').first);
      debugPrint('[AUTH] Realtime reconnect failed: $e');
    }
  }

  void _stopLifecycle() {
    _lifecycle?.stop();
    _lifecycle = null;
    // Cancel the Friday reminder so signed-out devices don't keep firing.
    // Fire-and-forget — never block the sign-out path on this.
    unawaited(FridayReminderService.cancel());
    // Disconnect Web PubSub so signed-out devices don't keep an open
    // WebSocket holding stale credentials.
    try {
      _realtime.disconnect();
    } catch (e) {
      debugPrint('[AUTH] Realtime disconnect failed: $e');
    }
  }

  @override
  void dispose() {
    _stopLifecycle();
    super.dispose();
  }
}
