import '../../../models/user_model.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

/// Layer 5 graceful re-login state.
///
/// Emitted when silent token acquisition fails with a "user session expired"
/// signature (Entra AADSTS700082 inactivity expiry, AADSTS500210 federated
/// refresh bug, or "no cached account" when we know a user was previously
/// signed in). The login screen shows `WelcomeBackDialog` instead of the
/// cold login screen; `email` pre-fills the MSAL loginHint for one-tap
/// re-authentication.
class AuthReloginRequired extends AuthState {
  final String? email;
  final String? displayName;
  const AuthReloginRequired({this.email, this.displayName});
}
