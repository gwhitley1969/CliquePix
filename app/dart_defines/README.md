# Build-time dart-defines

These files inject build-specific values via `--dart-define-from-file`. The values
here are **public** (cert fingerprints / redirect URIs), not secrets.

## `MSAL_ANDROID_REDIRECT_URI`

MSAL's Android redirect URI embeds `base64(SHA1(signing cert))`, which differs per
build because the debug keystore and the Play App Signing key are different certs.
`MsalConstants.androidRedirectUri` reads this define and **defaults to the release
value**, so production/CI builds are correct even with no flag (fail-safe).

| Build | Command |
|-------|---------|
| Local debug (`flutter run`, debug keystore) | `flutter run --dart-define-from-file=dart_defines/debug.json` |
| Release / Play App Signing | `flutter build appbundle --release` (default value is already the release hash) — or be explicit: `--dart-define-from-file=dart_defines/release.json` |

If you regenerate either hash (e.g. a new release keystore), update the matching
file here, the `<data>` path in `android/app/src/main/AndroidManifest.xml`, and the
redirect URI registered in the Entra app registration. See
`docs/SECURITY_AUDIT_2026-06-04.md` (AUTH-1) for how to compute the hash from the
Play App Signing certificate.
