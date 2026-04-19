import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';

final tokenStorageServiceProvider = Provider<TokenStorageService>((ref) {
  return TokenStorageService();
});

class TokenStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _lastRefreshTimeKey = 'last_refresh_time';
  static const _lastKnownUserKey = 'last_known_user';
  static const _lastKnownUserNameKey = 'last_known_user_name';
  static const _cachedUserModelKey = 'cached_user_model_v1';

  Future<bool> Function()? _refreshCallback;

  void setRefreshCallback(Future<bool> Function() callback) {
    _refreshCallback = callback;
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _lastRefreshTimeKey, value: DateTime.now().toIso8601String()),
    ]);
  }

  Future<DateTime?> getLastRefreshTime() async {
    final value = await _storage.read(key: _lastRefreshTimeKey);
    return value != null ? DateTime.tryParse(value) : null;
  }

  Future<bool> isTokenStale() async {
    final lastRefresh = await getLastRefreshTime();
    if (lastRefresh == null) return true;
    return DateTime.now().difference(lastRefresh).inHours >=
        AppConstants.tokenStaleThresholdHours;
  }

  Future<void> saveLastKnownUser(String email, String displayName) async {
    await Future.wait([
      _storage.write(key: _lastKnownUserKey, value: email),
      _storage.write(key: _lastKnownUserNameKey, value: displayName),
    ]);
  }

  Future<({String? email, String? name})> getLastKnownUser() async {
    final email = await _storage.read(key: _lastKnownUserKey);
    final name = await _storage.read(key: _lastKnownUserNameKey);
    return (email: email, name: name);
  }

  /// Persist the full UserModel JSON so a cold start can render the
  /// authenticated UI immediately (optimistic authentication) without waiting
  /// for a network round-trip. Background verification refreshes this after
  /// the app renders.
  Future<void> saveCachedUserModel(UserModel user) async {
    await _storage.write(
      key: _cachedUserModelKey,
      value: jsonEncode(user.toJson()),
    );
  }

  /// Returns the cached UserModel if present and parseable, else null.
  /// Failures (missing key, corrupt JSON) are treated as "no cache" — caller
  /// falls back to the unauthenticated bootstrap path.
  Future<UserModel?> getCachedUserModel() async {
    try {
      final raw = await _storage.read(key: _cachedUserModelKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> refreshToken() async {
    if (_refreshCallback != null) {
      return _refreshCallback!();
    }
    return false;
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
