# Flutter — Paywall Client + Trial Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the RevenueCat SDK + Paywalls v2 paywall to the Flutter app, gated so users without `effective_active` (subscribed OR in trial) are routed to `/paywall`; subscribed/trial users get the full app.

**Architecture:** A new `RevenueCatService` (lifecycle-mirroring `DmRealtimeService`) configures the SDK at deferred-init, logs the user in/out alongside the existing auth lifecycle, and presents the hosted paywall. The `entitlement` object (incl. `effective_active`, `in_trial`) rides inside `AuthAuthenticated.user`. The GoRouter `redirect` gates on `effective_active`. A purchase-success optimistic flag + 30s auto-recovery covers the webhook-delay race.

**Tech Stack:** Flutter, Riverpod, go_router, `purchases_flutter` + `purchases_ui_flutter` (RevenueCat). Tests via `flutter test`.

---

## Plan-wide context (read once)

**Plan 2 of 5.** Depends on **Plan 1 (backend) being DEPLOYED** — the client reads `entitlement.effective_active`/`in_trial` from `/api/auth/verify` + `/api/users/me`, which only exist after Plan 1 ships. Also depends on **Phase 1c of the base plan** (RevenueCat dashboard configured + public SDK keys captured) — those keys go into `revenuecat_constants.dart` (Task 1).

Baselines to preserve: `flutter analyze` 54-issue baseline; `flutter test` 87/87 (this plan ADDS tests). Per `feedback_always_flutter_clean.md`: run `flutter clean && flutter pub get` before any release build.

All paths are under `C:\backup dev03\CliquePix\app`. Run flutter commands from `app/`.

**Files:**
- Create: `lib/core/constants/revenuecat_constants.dart`, `lib/features/paywall/domain/entitlement_state.dart`, `lib/features/paywall/presentation/paywall_providers.dart`, `lib/features/paywall/presentation/paywall_screen.dart`, `lib/services/revenuecat_service.dart`, `test/entitlement_state_test.dart`
- Modify: `pubspec.yaml`, `lib/models/user_model.dart`, `lib/main.dart`, `lib/core/routing/app_router.dart`, `lib/app/shell_screen.dart`, `lib/features/auth/presentation/auth_providers.dart`, `lib/features/auth/domain/auth_repository.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/profile/presentation/token_diagnostics_screen.dart`

---

## Task 1: Dependencies, version bump, SDK key constants

**Files:**
- Modify: `pubspec.yaml:4` (version), `pubspec.yaml:50` (deps)
- Create: `lib/core/constants/revenuecat_constants.dart`

- [ ] **Step 1: Add the RevenueCat packages**

Run (from `app/`): `flutter pub add purchases_flutter purchases_ui_flutter`
Expected: both resolve; `pubspec.lock` updated. Do NOT hand-pin versions — accept the current RevenueCat-supported major.

- [ ] **Step 2: Bump the app version**

In `pubspec.yaml` line 4, change:
```yaml
version: 1.0.0+4
```
to:
```yaml
version: 1.0.0+5
```

- [ ] **Step 3: Create the SDK key constants**

Create `lib/core/constants/revenuecat_constants.dart` (paste the real keys captured in base-plan Phase 1c — `appl_...` iOS, `goog_...` Android):

```dart
import 'dart:io' show Platform;

/// RevenueCat public SDK keys. These are NOT secrets (they're shipped in the
/// app binary) — the Secret API Key + webhook bearer live in Key Vault on the
/// backend only. Captured from RevenueCat dashboard → Project settings → API Keys.
class RevenueCatConstants {
  RevenueCatConstants._();

  static const String _appleKey = 'appl_REPLACE_WITH_IOS_PUBLIC_KEY';
  static const String _googleKey = 'goog_REPLACE_WITH_ANDROID_PUBLIC_KEY';

  /// Platform-correct public key for Purchases.configure.
  static String get publicSdkKey => Platform.isIOS ? _appleKey : _googleKey;

  /// The offering identifier configured in the RevenueCat dashboard.
  static const String offeringId = 'default';

  /// The entitlement identifier gating Clique Pix Plus.
  static const String entitlementId = 'plus';
}
```

> The `_appleKey`/`_googleKey` placeholders are the ONLY values that must be filled from the dashboard before a real build — they are credentials, not code. Leave them as-is for code review; Gene replaces them at build time.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/constants/revenuecat_constants.dart
git commit -m "feat(paywall): add RevenueCat deps + SDK key constants, bump to 1.0.0+5"
```

---

## Task 2: `EntitlementState` model + `UserModel.entitlement` parsing

**Files:**
- Create: `lib/features/paywall/domain/entitlement_state.dart`
- Create: `test/entitlement_state_test.dart`
- Modify: `lib/models/user_model.dart:1-83`

- [ ] **Step 1: Write the failing test**

Create `test/entitlement_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/paywall/domain/entitlement_state.dart';
import 'package:clique_pix/models/user_model.dart';

void main() {
  group('EntitlementState.fromJson', () {
    test('parses an active trial', () {
      final e = EntitlementState.fromJson({
        'active': false,
        'product_id': null,
        'period_type': null,
        'will_renew': null,
        'expires_at': null,
        'store': null,
        'in_trial': true,
        'trial_ends_at': '2026-06-15T00:00:00.000Z',
        'effective_active': true,
      });
      expect(e.active, false);
      expect(e.inTrial, true);
      expect(e.effectiveActive, true);
      expect(e.trialEndsAt, DateTime.parse('2026-06-15T00:00:00.000Z'));
    });

    test('parses an active subscriber', () {
      final e = EntitlementState.fromJson({
        'active': true,
        'product_id': 'plus_annual',
        'period_type': 'normal',
        'will_renew': true,
        'expires_at': '2027-06-01T00:00:00.000Z',
        'store': 'APP_STORE',
        'in_trial': false,
        'trial_ends_at': null,
        'effective_active': true,
      });
      expect(e.active, true);
      expect(e.effectiveActive, true);
      expect(e.productId, 'plus_annual');
      expect(e.store, 'APP_STORE');
    });
  });

  group('UserModel.entitlement', () {
    test('defaults to EntitlementState.none when entitlement is absent (old backend)', () {
      final u = UserModel.fromJson({
        'id': 'u1',
        'display_name': 'Test',
        'email_or_phone': 't@example.com',
        'created_at': '2026-06-01T00:00:00.000Z',
      });
      expect(u.entitlement.effectiveActive, false);
      expect(u.entitlement.inTrial, false);
    });

    test('parses the entitlement object when present', () {
      final u = UserModel.fromJson({
        'id': 'u1',
        'display_name': 'Test',
        'email_or_phone': 't@example.com',
        'created_at': '2026-06-01T00:00:00.000Z',
        'entitlement': {
          'active': false,
          'in_trial': true,
          'trial_ends_at': '2026-06-15T00:00:00.000Z',
          'effective_active': true,
        },
      });
      expect(u.entitlement.effectiveActive, true);
      expect(u.entitlement.inTrial, true);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/entitlement_state_test.dart`
Expected: FAIL — `entitlement_state.dart` does not exist; `UserModel` has no `entitlement`.

- [ ] **Step 3: Create the model**

Create `lib/features/paywall/domain/entitlement_state.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Mirrors the backend `entitlement` object emitted by buildAuthUserResponse.
/// `effectiveActive` is the value the router gate keys off: subscribed OR in trial.
@immutable
class EntitlementState {
  final bool active;
  final String? productId;
  final String? periodType;
  final bool? willRenew;
  final DateTime? expiresAt;
  final String? store;
  final bool inTrial;
  final DateTime? trialEndsAt;
  final bool effectiveActive;

  const EntitlementState({
    required this.active,
    required this.effectiveActive,
    required this.inTrial,
    this.productId,
    this.periodType,
    this.willRenew,
    this.expiresAt,
    this.store,
    this.trialEndsAt,
  });

  /// Default for an old backend that doesn't send the entitlement object, or a
  /// brand-new unsubscribed/expired user. Gate fails closed.
  static const EntitlementState none = EntitlementState(
    active: false,
    effectiveActive: false,
    inTrial: false,
  );

  factory EntitlementState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return EntitlementState(
      active: (json['active'] as bool?) ?? false,
      productId: json['product_id'] as String?,
      periodType: json['period_type'] as String?,
      willRenew: json['will_renew'] as bool?,
      expiresAt: parseDate(json['expires_at']),
      store: json['store'] as String?,
      inTrial: (json['in_trial'] as bool?) ?? false,
      trialEndsAt: parseDate(json['trial_ends_at']),
      effectiveActive: (json['effective_active'] as bool?) ?? false,
    );
  }
}
```

- [ ] **Step 4: Wire into `UserModel`**

In `lib/models/user_model.dart`:

(a) Add the import at the top:
```dart
import 'package:clique_pix/features/paywall/domain/entitlement_state.dart';
```

(b) Add the field next to the others (after `createdAt`, ~line 10):
```dart
  final EntitlementState entitlement;
```

(c) Add to the constructor parameter list (with a default so existing call sites compile):
```dart
    this.entitlement = EntitlementState.none,
```

(d) In `fromJson` (lines 32-46), add before the closing `);`:
```dart
    entitlement: json['entitlement'] == null
        ? EntitlementState.none
        : EntitlementState.fromJson(json['entitlement'] as Map<String, dynamic>),
```

(e) In `copyWith` (lines 60-83), add an `EntitlementState? entitlement` param and `entitlement: entitlement ?? this.entitlement,` to the returned object.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/entitlement_state_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/paywall/domain/entitlement_state.dart lib/models/user_model.dart test/entitlement_state_test.dart
git commit -m "feat(paywall): EntitlementState model + UserModel parsing"
```

---

## Task 3: `RevenueCatService`

**Files:**
- Create: `lib/services/revenuecat_service.dart`

- [ ] **Step 1: Create the service**

Create `lib/services/revenuecat_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:clique_pix/core/constants/revenuecat_constants.dart';

/// Thin wrapper over the RevenueCat SDK. Lifecycle mirrors DmRealtimeService:
/// configure() once at deferred-init; logIn() on AuthAuthenticated; logOut()
/// on sign-out / resetSession. Never throws to callers — failures are logged.
class RevenueCatService {
  bool _configured = false;

  Future<void> configure() async {
    if (_configured) return;
    try {
      await Purchases.setLogLevel(LogLevel.warn);
      await Purchases.configure(
        PurchasesConfiguration(RevenueCatConstants.publicSdkKey),
      );
      _configured = true;
    } catch (e) {
      debugPrint('[RC] configure failed: $e');
    }
  }

  /// Alias the anonymous RC app-user id to our backend user id. Call AFTER
  /// sign-in. Do NOT call before auth.
  Future<void> logIn(String userId) async {
    if (!_configured) await configure();
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('[RC] logIn failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // RC throws if already anonymous — benign.
      debugPrint('[RC] logOut (benign if anonymous): $e');
    }
  }

  /// Present the hosted Paywalls v2 paywall. Returns true if the user ended the
  /// flow with the `plus` entitlement active (purchased or restored).
  Future<bool> presentPaywall() async {
    try {
      final result = await RevenueCatUI.presentPaywall();
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active
          .containsKey(RevenueCatConstants.entitlementId);
      // result is also available for telemetry: PaywallResult enum.
    } catch (e) {
      debugPrint('[RC] presentPaywall failed: $e');
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active
          .containsKey(RevenueCatConstants.entitlementId);
    } catch (e) {
      debugPrint('[RC] restore failed: $e');
      return false;
    }
  }

  Future<void> showManageSubscriptions() async {
    try {
      await Purchases.showManageSubscriptions();
    } catch (e) {
      debugPrint('[RC] showManageSubscriptions failed: $e');
    }
  }

  Future<void> invalidateCache() async {
    try {
      await Purchases.invalidateCustomerInfoCache();
    } catch (e) {
      debugPrint('[RC] invalidateCache failed: $e');
    }
  }
}
```

> The exact `RevenueCatUI.presentPaywall()` / `PaywallResult` API surface can shift across SDK majors — if `flutter analyze` flags a signature mismatch after Task 1's `pub add`, adjust to the resolved version's API (consult RevenueCat's `purchases_ui_flutter` docs). The behavior (present paywall, then check `entitlements.active['plus']`) is stable.

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/services/revenuecat_service.dart`
Expected: no NEW errors (warnings about the SDK API only if a signature shifted — fix per the note above).

- [ ] **Step 3: Commit**

```bash
git add lib/services/revenuecat_service.dart
git commit -m "feat(paywall): RevenueCatService lifecycle wrapper"
```

---

## Task 4: Paywall providers + paywall screen

**Files:**
- Create: `lib/features/paywall/presentation/paywall_providers.dart`
- Create: `lib/features/paywall/presentation/paywall_screen.dart`

- [ ] **Step 1: Create the providers**

Create `lib/features/paywall/presentation/paywall_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clique_pix/services/revenuecat_service.dart';
import 'package:clique_pix/features/auth/presentation/auth_providers.dart';
import 'package:clique_pix/features/auth/presentation/auth_state.dart';

final revenueCatServiceProvider =
    Provider<RevenueCatService>((ref) => RevenueCatService());

/// Optimistic override set true the instant a purchase succeeds, so the router
/// dismisses the paywall before the backend webhook lands. Cleared once the
/// backend confirms entitlement (next auth refresh) — see paywall_screen.
final optimisticEntitlementProvider = StateProvider<bool>((ref) => false);

/// THE gate value. True when the backend says effective_active OR we're in the
/// optimistic post-purchase window.
final hasAppAccessProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  final optimistic = ref.watch(optimisticEntitlementProvider);
  final backend =
      auth is AuthAuthenticated && auth.user.entitlement.effectiveActive;
  return backend || optimistic;
}, name: 'hasAppAccessProvider');
```

- [ ] **Step 2: Create the paywall screen**

Create `lib/features/paywall/presentation/paywall_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/features/auth/presentation/auth_providers.dart';
import 'package:clique_pix/services/telemetry_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});
  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
            tooltip: 'Account',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: PaywallView(
        onPurchaseCompleted: (customerInfo, storeTransaction) =>
            _onEntitlementGranted('purchase'),
        onRestoreCompleted: (customerInfo) {
          if (customerInfo.entitlements.active.containsKey('plus')) {
            _onEntitlementGranted('restore');
          }
        },
      ),
    );
  }

  void _onEntitlementGranted(String source) {
    ref.read(telemetryServiceProvider).record('purchase_succeeded',
        extra: {'source': source});
    // Optimistically dismiss the paywall; router redirect fires off this.
    ref.read(optimisticEntitlementProvider.notifier).state = true;
    // Kick a backend refresh so the authoritative entitlement lands; clear the
    // optimistic flag once it does. Auto-recovery after 30s if the webhook is slow.
    _reconcile();
  }

  Future<void> _reconcile() async {
    final auth = ref.read(authStateProvider.notifier);
    try {
      await auth.refreshEntitlement(); // see Task 7 (auth_providers)
    } catch (_) {/* optimistic flag carries the UI until next verify */}
  }
}
```

> `PaywallView`'s callback names (`onPurchaseCompleted`, `onRestoreCompleted`) match `purchases_ui_flutter`'s current API. If Task 1 resolved a major where they differ, adjust to the resolved signatures. `refreshEntitlement()` on the auth notifier is added in Task 7.

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze lib/features/paywall/`
Expected: no new errors (SDK signature adjustments per notes only).

- [ ] **Step 4: Commit**

```bash
git add lib/features/paywall/presentation/
git commit -m "feat(paywall): paywall providers + hosted paywall screen"
```

---

## Task 5: Router gate on `effective_active`

**Files:**
- Modify: `lib/core/routing/app_router.dart:30-51` (redirect) + add `/paywall` route

- [ ] **Step 1: Add the `/paywall` route**

In `lib/core/routing/app_router.dart`, add a top-level route (sibling of `/login`, OUTSIDE the shell so it has no bottom nav):

```dart
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const PaywallScreen(),
      ),
```
Add the import: `import 'package:clique_pix/features/paywall/presentation/paywall_screen.dart';`

- [ ] **Step 2: Extend the redirect**

Replace the `redirect:` body (lines 35-50) with one that also watches access. First add `final hasAccess = ref.watch(hasAppAccessProvider);` after line 32 (`final authState = ...`), and the import `import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';`. Then:

```dart
    redirect: (context, state) {
      final isAuthenticated = authState is AuthAuthenticated;
      final loc = state.matchedLocation;
      final isLoginRoute = loc == '/login';

      // Unauthenticated → login (unchanged).
      if (!isAuthenticated && !isLoginRoute) {
        final redirect = loc;
        if (redirect != '/events') return '/login?redirect=$redirect';
        return '/login';
      }
      if (isAuthenticated && isLoginRoute) {
        final redirect = state.uri.queryParameters['redirect'];
        return redirect ?? '/events';
      }

      // Authenticated but no access → paywall, except the allowlist.
      const allowlist = {'/paywall', '/profile', '/login'};
      if (isAuthenticated && !hasAccess && !allowlist.contains(loc)) {
        return '/paywall';
      }
      // Authenticated WITH access sitting on the paywall → send to events.
      if (isAuthenticated && hasAccess && loc == '/paywall') {
        return '/events';
      }
      return null;
    },
```

- [ ] **Step 3: Verify routing manually (no unit test for GoRouter redirect)**

Run: `flutter analyze lib/core/routing/app_router.dart`
Expected: no new errors. Behavioral verification happens in Task 11 on-device (trial user → full app; expired-trial user → paywall).

- [ ] **Step 4: Commit**

```bash
git add lib/core/routing/app_router.dart
git commit -m "feat(paywall): router gates on effective_active, adds /paywall"
```

---

## Task 6: Hide bottom nav on the paywall

**Files:**
- Modify: `lib/app/shell_screen.dart:12-28`

- [ ] **Step 1: Conditionally render the nav**

The shell only wraps `/events`,`/cliques`,`/notifications`,`/profile`. The paywall is OUTSIDE the shell (Task 5), so it already has no bottom nav. The only in-shell route reachable without access is `/profile`. Make the shell hide the nav when the user lacks access (so the gated Profile shown from the paywall has no nav):

Convert `ShellScreen` to a `ConsumerWidget` (if not already) and gate the bar. Replace the `build` (lines 12-28):

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccess = ref.watch(hasAppAccessProvider);
    return Scaffold(
      body: RealtimeProviderInvalidator(child: navigationShell),
      bottomNavigationBar: hasAccess
          ? AppBottomNav(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            )
          : null,
    );
  }
```
Add imports: `package:flutter_riverpod/flutter_riverpod.dart` and `paywall_providers.dart`. If `ShellScreen` was a `StatelessWidget`, change to `ConsumerWidget`.

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/app/shell_screen.dart`
Expected: no new errors.
```bash
git add lib/app/shell_screen.dart
git commit -m "feat(paywall): hide bottom nav when no app access"
```

---

## Task 7: Wire RC login/logout into auth lifecycle + add `refreshEntitlement`

**Files:**
- Modify: `lib/features/auth/presentation/auth_providers.dart:327-357` (_startLifecycle), `:413-426` (_stopLifecycle); add `refreshEntitlement`
- Modify: `lib/features/auth/domain/auth_repository.dart:154-162` (resetSession)

- [ ] **Step 1: logIn on lifecycle start**

In `_startLifecycle`'s post-frame block (after the `_connectRealtime()` line ~352), add:
```dart
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      FridayReminderService.scheduleOrReschedule(telemetry: _telemetryRecord)
          .catchError((Object e) {
        debugPrint('[AUTH] Friday reminder schedule failed: $e');
      }),
    );
    unawaited(_connectRealtime());
    final user = state;
    if (user is AuthAuthenticated) {
      unawaited(_ref.read(revenueCatServiceProvider).logIn(user.user.id));
    }
  });
```
This needs `Ref` access. The notifier already reads other providers — use the existing `ref`/`_ref` field (match the file's convention; the Explore report shows providers are read via `ref`). Add import `package:clique_pix/features/paywall/presentation/paywall_providers.dart`.

- [ ] **Step 2: logOut on lifecycle stop**

In `_stopLifecycle` (lines 413-426), add before/after the realtime disconnect:
```dart
    unawaited(_ref.read(revenueCatServiceProvider).logOut());
```

- [ ] **Step 3: Add `refreshEntitlement`**

Add a method on `AuthNotifier` (called by the paywall screen Task 4 and the Profile refresh tile Task 9):
```dart
  /// Force the backend to re-sync entitlement from RevenueCat's REST API and
  /// fold the fresh user into state. Clears the optimistic flag. Used after a
  /// purchase when the webhook is slow.
  Future<void> refreshEntitlement() async {
    try {
      final user = await _repository.refreshEntitlement(); // POST /api/users/me/entitlement/refresh
      if (state is AuthAuthenticated) {
        state = AuthAuthenticated(user);
      }
      _ref.read(optimisticEntitlementProvider.notifier).state = false;
    } catch (e) {
      debugPrint('[AUTH] refreshEntitlement failed: $e');
    }
  }
```
Add `refreshEntitlement()` to `AuthRepository` calling `POST /api/users/me/entitlement/refresh` (the endpoint built in base-plan Phase 2) and returning `UserModel.fromJson(data)`. Mirror an existing repository POST (e.g. how `verifyAndGetUser` calls the API client).

- [ ] **Step 4: logOut in resetSession**

In `auth_repository.dart` `resetSession()` (lines 154-162), add inside the try after `pca.signOut()`:
```dart
      try { await Purchases.logOut(); } catch (_) {}
```
Add import `package:purchases_flutter/purchases_flutter.dart`.

- [ ] **Step 5: Verify + commit**

Run: `flutter analyze lib/features/auth/`
Expected: no new errors.
```bash
git add lib/features/auth/
git commit -m "feat(paywall): RC logIn/logOut in auth lifecycle + refreshEntitlement"
```

---

## Task 8: Configure RC at deferred init

**Files:**
- Modify: `lib/main.dart:214-299` (performDeferredInit)

- [ ] **Step 1: Configure the SDK**

In `performDeferredInit()`, after `_deferredInitDone = true;` (line ~219), add:
```dart
  try {
    await RevenueCatService().configure();
  } catch (e) {
    debugPrint('[CliquePix] RevenueCat configure failed: $e');
  }
```
Add import `package:clique_pix/services/revenuecat_service.dart`.

> `configure()` is idempotent (the service's `_configured` flag) and `logIn` re-configures if needed, so this is safe even if the provider instance differs from the one used in auth lifecycle.

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/main.dart`
Expected: no new errors.
```bash
git add lib/main.dart
git commit -m "feat(paywall): configure RevenueCat in performDeferredInit"
```

---

## Task 9: Profile subscription tiles + diagnostics section

**Files:**
- Modify: `lib/features/profile/presentation/profile_screen.dart` (add a `_SettingsGroup` ~line 245, before Sign Out)
- Modify: `lib/features/profile/presentation/token_diagnostics_screen.dart:119-129` (add entitlement stat tiles)

- [ ] **Step 1: Add the subscription settings group**

Insert a new `_SettingsGroup` before the Sign Out group (~line 245 per Explore report):
```dart
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.workspace_premium_outlined,
              iconColors: [AppColors.electricAqua, AppColors.deepBlue],
              title: 'Manage Subscription',
              onTap: () =>
                  ref.read(revenueCatServiceProvider).showManageSubscriptions(),
            ),
            _SettingsTile(
              icon: Icons.restore_rounded,
              iconColors: [AppColors.deepBlue, AppColors.violetAccent],
              title: 'Restore Purchases',
              showDivider: false,
              onTap: () async {
                final ok =
                    await ref.read(revenueCatServiceProvider).restorePurchases();
                if (ok) await ref.read(authStateProvider.notifier).refreshEntitlement();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Purchases restored' : 'No purchases to restore'),
                  ));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
```
Ensure `revenueCatServiceProvider` + `authStateProvider` are imported in this screen.

- [ ] **Step 2: Add the entitlement section to Token Diagnostics**

In `token_diagnostics_screen.dart`, after the battery-exempt `_statTile` (line 129), read the entitlement from auth state and add:
```dart
            Builder(builder: (context) {
              final auth = ref.watch(authStateProvider);
              final e = auth is AuthAuthenticated
                  ? auth.user.entitlement
                  : EntitlementState.none;
              return Column(children: [
                _statTile('Entitlement active', e.active.toString()),
                _statTile('In trial', e.inTrial.toString()),
                _statTile('Effective access', e.effectiveActive.toString()),
                _statTile('Trial ends', e.trialEndsAt?.toLocal().toString() ?? '—'),
                _statTile('Product', e.productId ?? '—'),
                _statTile('Period', e.periodType ?? '—'),
                _statTile('Store', e.store ?? '—'),
              ]);
            }),
```
Add imports for `authStateProvider`, `auth_state.dart`, and `entitlement_state.dart`. Convert the screen to a `ConsumerStatefulWidget`/`ConsumerState` if it isn't already reading `ref` (the Explore report shows it reads diagnostics state — confirm it has a `ref`).

- [ ] **Step 3: Verify + commit**

Run: `flutter analyze lib/features/profile/`
Expected: no new errors.
```bash
git add lib/features/profile/
git commit -m "feat(paywall): Manage Subscription/Restore tiles + diagnostics section"
```

---

## Task 10: Purchase-success auto-recovery (30s safety net)

**Files:**
- Modify: `lib/features/paywall/presentation/paywall_screen.dart`

- [ ] **Step 1: Add the 30s auto-recovery**

The optimistic flag (Task 4) dismisses the paywall instantly; `refreshEntitlement` pulls authoritative state. Add a bounded retry so a slow webhook still resolves without leaving the optimistic flag set forever. Replace `_reconcile()` in `paywall_screen.dart`:
```dart
  Future<void> _reconcile() async {
    final auth = ref.read(authStateProvider.notifier);
    // Try immediately, then once more after ~10s, then give up gracefully at 30s.
    for (final delay in [Duration.zero, const Duration(seconds: 10), const Duration(seconds: 20)]) {
      if (delay > Duration.zero) await Future.delayed(delay);
      await auth.refreshEntitlement();
      final active = ref.read(authStateProvider) is AuthAuthenticated &&
          (ref.read(authStateProvider) as AuthAuthenticated).user.entitlement.effectiveActive;
      if (active) return; // backend confirmed; optimistic flag already cleared
    }
    // Backend still not confirmed after 30s. The optimistic flag keeps the user
    // OUT of the paywall (they paid); they land on /events. Next normal auth
    // verify will reconcile. No user-facing error after a successful charge.
  }
```

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/features/paywall/`
Expected: no new errors.
```bash
git add lib/features/paywall/presentation/paywall_screen.dart
git commit -m "feat(paywall): 30s post-purchase entitlement auto-recovery"
```

---

## Task 11: Full verification

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: 54-issue baseline preserved (no NEW issues).

- [ ] **Step 2: Test**

Run: `flutter test`
Expected: 87 baseline + 4 new (entitlement) = 91 passing.

- [ ] **Step 3: Clean release build (per `feedback_always_flutter_clean.md`)**

Run: `flutter clean && flutter pub get && flutter build apk --release`
Expected: builds green. (iOS: `flutter build ios --release --no-codesign`.)

- [ ] **Step 4: On-device smoke (after Plan 1 deployed + RC keys filled)**

- Trial user (fresh account, within 7 days): signs in → lands on `/events`, bottom nav visible, NO paywall.
- Expired-trial unsubscribed user: signs in → `/paywall`, bottom nav hidden, account icon → Profile reachable.
- Subscribe (sandbox/license tester) → paywall dismisses within ~3s, lands on `/events`.
- Sign out → sign in different account → correct gate per that account (verifies the 2026-05-06 cross-account invalidation still holds with entitlement state).

- [ ] **Step 5: Commit any fixups, then the plan is done.**

---

## Self-review notes (already applied)

- **Spec coverage:** §3 (router gate on `effective_active`, paywall placement on trial lapse, invite-loop preserved via trial) — Tasks 5,6. Base-plan Phase 3 (RC SDK, paywall UI, lifecycle login/logout, resetSession logout, profile tiles, diagnostics, race window) — Tasks 1,3,4,7,8,9,10.
- **Type consistency:** `EntitlementState.effectiveActive` (Dart camelCase) ↔ `effective_active` (JSON) parsed in Task 2; `hasAppAccessProvider` consumed identically in router (Task 5) + shell (Task 6); `refreshEntitlement()` defined in Task 7 and called in Tasks 4,9,10.
- **Known SDK-surface risk:** `purchases_ui_flutter` callback/method names are pinned to its current major; Tasks 3,4 flag where to adjust if `pub add` resolves a different major.
