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
