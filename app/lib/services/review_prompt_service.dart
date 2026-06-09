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
