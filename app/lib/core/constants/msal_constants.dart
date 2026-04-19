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

  static const androidRedirectUri =
      'msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D';

  static const androidConfigFilePath = 'assets/msal_config.json';
}
