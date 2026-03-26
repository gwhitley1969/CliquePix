class Environment {
  Environment._();

  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  static bool get isDev => env == 'dev';
  static bool get isProd => env == 'prod';

  // API base URLs (Front Door endpoints)
  static String get apiBaseUrl {
    switch (env) {
      case 'prod':
        return 'https://api.clique-pix.com';
      default:
        return 'https://api.clique-pix.com';
    }
  }

  // Entra External ID
  static const entraTenantId = String.fromEnvironment('ENTRA_TENANT_ID');
  static const entraClientId = String.fromEnvironment('ENTRA_CLIENT_ID');

  static String get entraAuthority =>
      'https://cliquepix.ciamlogin.com/$entraTenantId';

  // Deep link domain
  static const deepLinkDomain = 'clique-pix.com';
}
