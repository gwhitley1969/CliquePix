/// Centralized MSAL configuration so the main Dart isolate, the WorkManager
/// isolate (Layer 4), and the FCM background handler isolate (Layer 2, silent
/// push) all build a `SingleAccountPca` from the same source of truth.
///
/// Keep in sync with:
///   - `app/assets/msal_config.json`
///   - Azure Entra app registration 7db01206-135b-4a34-a4d5-2622d1a888bf
///   - `backend/src/shared/middleware/authMiddleware.ts` (tenant + audience)
class MsalConstants {
  MsalConstants._();

  static const clientId = '7db01206-135b-4a34-a4d5-2622d1a888bf';

  static const authority =
      'https://cliquepix.ciamlogin.com/cliquepix.onmicrosoft.com/';

  /// Custom API scope — required for MSAL to return an app-scoped access
  /// token (signed by our CIAM tenant) instead of a Microsoft Graph token
  /// (signed by Graph's keys, which the backend cannot validate).
  static const scopes = <String>[
    'api://7db01206-135b-4a34-a4d5-2622d1a888bf/access_as_user',
  ];

  /// MSAL Android redirect URI = `msauth://<package>/<base64(SHA1(signing cert))>`.
  ///
  /// msal_auth overwrites app/assets/msal_config.json's `redirect_uri` with THIS
  /// value at PCA-creation time (see msal_auth `utils.dart`), so this const — not
  /// the JSON — is the single source of truth that reaches native MSAL.
  ///
  /// The hash MUST match the cert that signs the RUNNING build, so it is injected
  /// at build time:
  ///   • Default below = the RELEASE / Play App Signing key hash → release & CI
  ///     builds are correct even if the dart-define is forgotten (fail-safe: a
  ///     forgotten flag fails toward production-correct, not toward a broken prod).
  ///   • Local debug builds (debug keystore) opt into the debug hash via:
  ///       flutter run --dart-define-from-file=dart_defines/debug.json
  ///
  /// Both hashes are registered as redirect URIs in the Entra app registration
  /// (7db01206-…) and as `<data>` paths in AndroidManifest.xml. These are public
  /// cert fingerprints, not secrets. See docs/SECURITY_AUDIT_2026-06-04.md (AUTH-1).
  static const androidRedirectUri = String.fromEnvironment(
    'MSAL_ANDROID_REDIRECT_URI',
    defaultValue:
        'msauth://com.cliquepix.clique_pix/4FsaiJ4wJWgM09R%2FhUh3osYJhgg%3D',
  );

  static const androidConfigFilePath = 'assets/msal_config.json';
}
