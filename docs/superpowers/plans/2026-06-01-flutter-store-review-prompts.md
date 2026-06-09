# Flutter — Native Store Review Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask happy users to rate CLIQUE Pix on the App Store / Play Store via `in_app_review`, triggered after their 3rd successful media upload (counted across sessions), with a frequency cap and a manual "Rate CLIQUE Pix" tile in Profile.

**Architecture:** A `ReviewPromptService` owns all eligibility logic (pure, unit-tested) and SharedPreferences state (upload counter, last-request timestamp). The photo and video upload success paths call `maybeRequestReview()`. The OS decides whether to actually show the system prompt; we never assume it did.

**Tech Stack:** Flutter, `in_app_review`, `shared_preferences`. Tests via `flutter test`.

---

## Plan-wide context (read once)

**Plan 3 of 5.** Fully independent of the paywall (Plans 1/2) — can ship in any order. Baselines: `flutter analyze` 54-issue baseline; `flutter test` (adds tests). All paths under `C:\backup dev03\CliquePix\app`; run flutter commands from `app/`.

Hook points confirmed in the codebase:
- Photo success: `lib/features/photos/presentation/camera_capture_screen.dart` — after `confirmUpload(...)` returns (~line 145).
- Video success: `lib/features/videos/presentation/video_upload_screen.dart` — after `notifier.succeed(result.videoId, ...)` (~line 94).
- Telemetry: `lib/services/telemetry_service.dart` — `void record(String event, {String? errorCode, Map<String,String>? extra})`, provider `telemetryServiceProvider`.
- SharedPreferences pattern: `lib/features/auth/domain/battery_optimization_service.dart` (static const keys + `getBool`/`setBool`).
- Profile tiles: `lib/features/profile/presentation/profile_screen.dart` `_SettingsTile`/`_SettingsGroup` (first group lines 121-244).

**Files:**
- Create: `lib/services/review_prompt_service.dart`, `test/review_prompt_service_test.dart`
- Modify: `pubspec.yaml` (dep), `camera_capture_screen.dart`, `video_upload_screen.dart`, `profile_screen.dart`

---

## Task 1: Add the dependency

**Files:** Modify `pubspec.yaml`

- [ ] **Step 1: Add `in_app_review`**

Run (from `app/`): `flutter pub add in_app_review`
Expected: resolves; `pubspec.lock` updated.

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(review): add in_app_review dependency"
```

---

## Task 2: `ReviewPromptService` — eligibility logic (TDD)

The decision of whether to prompt is a pure function of (upload count, last-request time, now). Make it testable in isolation, separate from the side-effecting `requestReview()` call.

**Files:**
- Create: `lib/services/review_prompt_service.dart`
- Create: `test/review_prompt_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/review_prompt_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/services/review_prompt_service.dart';

void main() {
  const minUploads = ReviewPromptService.minUploadsBeforePrompt; // 3
  final now = DateTime(2026, 6, 10);

  group('shouldPrompt', () {
    test('false below the upload threshold', () {
      expect(
        ReviewPromptService.shouldPrompt(
            uploadCount: minUploads - 1, lastRequestedAt: null, now: now),
        false,
      );
    });

    test('true at the threshold with no prior request', () {
      expect(
        ReviewPromptService.shouldPrompt(
            uploadCount: minUploads, lastRequestedAt: null, now: now),
        true,
      );
    });

    test('false when within the cooldown window', () {
      final recent = now.subtract(const Duration(days: 30));
      expect(
        ReviewPromptService.shouldPrompt(
            uploadCount: minUploads + 5, lastRequestedAt: recent, now: now),
        false,
      );
    });

    test('true again after the cooldown elapses', () {
      final old = now.subtract(const Duration(days: 121));
      expect(
        ReviewPromptService.shouldPrompt(
            uploadCount: minUploads + 5, lastRequestedAt: old, now: now),
        true,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/review_prompt_service_test.dart`
Expected: FAIL — `review_prompt_service.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/services/review_prompt_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nudges happy users to rate the app at the right moment. All eligibility
/// rules live in the pure [shouldPrompt] so they can be unit-tested without
/// the OS prompt or SharedPreferences.
class ReviewPromptService {
  ReviewPromptService._();

  static const int minUploadsBeforePrompt = 3;
  static const Duration cooldown = Duration(days: 120);

  static const _uploadCountKey = 'review_successful_upload_count';
  static const _lastRequestedKey = 'review_last_requested_at_ms';

  /// Pure eligibility decision. Never prompt below the upload threshold, and
  /// never within [cooldown] of a prior request (the OS throttles too, but we
  /// avoid even asking so the OS budget is spent only on genuine happy moments).
  static bool shouldPrompt({
    required int uploadCount,
    required DateTime? lastRequestedAt,
    required DateTime now,
  }) {
    if (uploadCount < minUploadsBeforePrompt) return false;
    if (lastRequestedAt != null && now.difference(lastRequestedAt) < cooldown) {
      return false;
    }
    return true;
  }

  /// Call from a media-upload SUCCESS path only (never from an error path).
  /// Increments the counter, then requests the OS review prompt if eligible.
  /// Fire-and-forget; never throws to the caller.
  static Future<void> recordSuccessfulUploadAndMaybePrompt({
    void Function(String event, {Map<String, String>? extra})? track,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_uploadCountKey) ?? 0) + 1;
      await prefs.setInt(_uploadCountKey, count);

      final lastMs = prefs.getInt(_lastRequestedKey);
      final last =
          lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

      if (!shouldPrompt(
          uploadCount: count, lastRequestedAt: last, now: DateTime.now())) {
        track?.call('review_prompt_skipped',
            extra: {'reason': count < minUploadsBeforePrompt ? 'below_threshold' : 'cooldown'});
        return;
      }

      final review = InAppReview.instance;
      if (!await review.isAvailable()) {
        track?.call('review_prompt_skipped', extra: {'reason': 'unavailable'});
        return;
      }

      await review.requestReview();
      await prefs.setInt(_lastRequestedKey, DateTime.now().millisecondsSinceEpoch);
      track?.call('review_prompt_requested', extra: {'upload_count': '$count'});
    } catch (e) {
      debugPrint('[Review] maybePrompt failed: $e');
    }
  }

  /// Manual path from the Profile "Rate CLIQUE Pix" tile. Always opens the
  /// store listing (not throttled). [appStoreId] is the numeric App Store ID.
  static Future<void> openStoreListing(
      {required String appStoreId,
      void Function(String event, {Map<String, String>? extra})? track}) async {
    try {
      await InAppReview.instance.openStoreListing(appStoreId: appStoreId);
      track?.call('review_store_listing_opened');
    } catch (e) {
      debugPrint('[Review] openStoreListing failed: $e');
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/review_prompt_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/review_prompt_service.dart test/review_prompt_service_test.dart
git commit -m "feat(review): ReviewPromptService with unit-tested eligibility"
```

---

## Task 3: Hook the photo upload success path

**Files:** Modify `lib/features/photos/presentation/camera_capture_screen.dart:145`

- [ ] **Step 1: Call the service after a confirmed upload**

Immediately after `debugPrint('[CliquePix] _upload: confirm complete');` (~line 145, after `confirmUpload(...)` returns and before the temp-file cleanup), add:

```dart
        unawaited(ReviewPromptService.recordSuccessfulUploadAndMaybePrompt(
          track: (event, {extra}) =>
              ref.read(telemetryServiceProvider).record(event, extra: extra),
        ));
```
Add imports: `package:clique_pix/services/review_prompt_service.dart`, `package:clique_pix/services/telemetry_service.dart` (if not present), and `dart:async` for `unawaited` (if not already imported).

> Placing it AFTER `confirmUpload` returns guarantees we only count server-confirmed uploads, never failed ones — the method is the success boundary.

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/features/photos/presentation/camera_capture_screen.dart`
Expected: no new errors.
```bash
git add lib/features/photos/presentation/camera_capture_screen.dart
git commit -m "feat(review): prompt after successful photo upload"
```

---

## Task 4: Hook the video upload success path

**Files:** Modify `lib/features/videos/presentation/video_upload_screen.dart:94`

- [ ] **Step 1: Call the service after a successful commit**

Immediately after `notifier.succeed(result.videoId, previewUrl: result.previewUrl);` (~line 94), add:

```dart
        unawaited(ReviewPromptService.recordSuccessfulUploadAndMaybePrompt(
          track: (event, {extra}) =>
              ref.read(telemetryServiceProvider).record(event, extra: extra),
        ));
```
Add imports as in Task 3 (the file already uses `telemetry` per the Explore report — reuse the existing `telemetryServiceProvider` reference if one is in scope; otherwise `ref.read`).

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/features/videos/presentation/video_upload_screen.dart`
Expected: no new errors.
```bash
git add lib/features/videos/presentation/video_upload_screen.dart
git commit -m "feat(review): prompt after successful video upload"
```

---

## Task 5: "Rate CLIQUE Pix" Profile tile

**Files:** Modify `lib/features/profile/presentation/profile_screen.dart:121-244`

- [ ] **Step 1: Add the tile to the first settings group**

In the first `_SettingsGroup` (lines 121-244), set the current last tile ("Contact Us") `showDivider: true`, and add a new last tile:

```dart
            _SettingsTile(
              icon: Icons.star_outline_rounded,
              iconColors: [const Color(0xFFFBBF24), AppColors.electricAqua],
              title: 'Rate CLIQUE Pix',
              showDivider: false,
              onTap: () => ReviewPromptService.openStoreListing(
                appStoreId: '6766294274',
                track: (event, {extra}) =>
                    ref.read(telemetryServiceProvider).record(event, extra: extra),
              ),
            ),
```
Add imports for `review_prompt_service.dart` + `telemetry_service.dart` if not present. `6766294274` is the CLIQUE Pix App Store ID (per GENE.md).

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze lib/features/profile/presentation/profile_screen.dart`
Expected: no new errors.
```bash
git add lib/features/profile/presentation/profile_screen.dart
git commit -m "feat(review): manual 'Rate CLIQUE Pix' tile in Profile"
```

---

## Task 6: Full verification

- [ ] **Step 1: Analyze + test**

Run: `flutter analyze` → 54-issue baseline preserved.
Run: `flutter test` → all prior tests + 4 new review tests pass.

- [ ] **Step 2: Clean release build**

Run: `flutter clean && flutter pub get && flutter build apk --release`
Expected: green.

- [ ] **Step 3: On-device smoke**

- Upload media 3× across app restarts → on the 3rd, the OS review sheet MAY appear (Android shows it more reliably than iOS; Apple throttles). Token Diagnostics / App Insights shows `review_prompt_requested`.
- Upload a 4th time within the same window → `review_prompt_skipped { reason: cooldown }`, no sheet.
- Profile → "Rate CLIQUE Pix" → store listing opens (always works).
- A failed upload does NOT increment the counter (verify by forcing an upload error, then a success — count advances by exactly 1).

---

## Self-review notes (already applied)

- **Spec coverage:** §4 fully — `in_app_review` (Task 1), trigger on 3rd cross-session success (Tasks 2-4), guards: availability + cooldown + success-only (Task 2 logic + hook placement), manual `openStoreListing` tile (Task 5), telemetry `review_prompt_requested`/`_skipped`/`_store_listing_opened` (Task 2).
- **Type consistency:** `recordSuccessfulUploadAndMaybePrompt({track})` and `openStoreListing({appStoreId, track})` signatures match their call sites in Tasks 3,4,5; `minUploadsBeforePrompt`/`cooldown` constants referenced consistently in tests + logic.
- **Independence:** no dependency on Plans 1/2; safe to ship standalone.
