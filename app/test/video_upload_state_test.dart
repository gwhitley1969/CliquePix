import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/videos/presentation/videos_providers.dart';

void main() {
  // ─── VideoUploadState ──────────────────────────────────────────────────

  group('VideoUploadState', () {
    test('default state is idle', () {
      const state = VideoUploadState();
      expect(state.isUploading, isFalse);
      expect(state.progress, 0.0);
      expect(state.statusText, '');
      expect(state.errorText, isNull);
      expect(state.videoId, isNull);
      expect(state.previewUrl, isNull);
    });

    test('copyWith updates progress', () {
      const state = VideoUploadState(isUploading: true, progress: 0.5);
      final updated = state.copyWith(progress: 0.75);
      expect(updated.progress, 0.75);
      expect(updated.isUploading, isTrue);
    });

    test('copyWith can null-reset errorText', () {
      const state = VideoUploadState(errorText: 'Failed');
      final cleared = state.copyWith(errorText: null);
      expect(cleared.errorText, isNull);
    });

    test('copyWith preserves fields not specified', () {
      const state = VideoUploadState(
        isUploading: true,
        progress: 0.5,
        statusText: 'Uploading',
        videoId: 'vid-1',
      );
      final updated = state.copyWith(progress: 0.8);
      expect(updated.isUploading, isTrue);
      expect(updated.statusText, 'Uploading');
      expect(updated.videoId, 'vid-1');
    });
  });

  // ─── VideoUploadNotifier ───────────────────────────────────────────────

  group('VideoUploadNotifier', () {
    late VideoUploadNotifier notifier;

    setUp(() {
      notifier = VideoUploadNotifier();
    });

    test('initial state is idle', () {
      expect(notifier.state.isUploading, isFalse);
      expect(notifier.state.progress, 0.0);
    });

    test('start() sets uploading state', () {
      notifier.start('Preparing...');
      expect(notifier.state.isUploading, isTrue);
      expect(notifier.state.progress, 0.0);
      expect(notifier.state.statusText, 'Preparing...');
      expect(notifier.state.errorText, isNull);
    });

    test('updateProgress() updates progress and optional status', () {
      notifier.start('Starting...');
      notifier.updateProgress(0.5, 'Uploading 50%');
      expect(notifier.state.progress, 0.5);
      expect(notifier.state.statusText, 'Uploading 50%');
    });

    test('updateProgress() preserves status when not provided', () {
      notifier.start('Starting...');
      notifier.updateProgress(0.5);
      expect(notifier.state.progress, 0.5);
      expect(notifier.state.statusText, 'Starting...');
    });

    test('succeed() sets complete state with videoId', () {
      notifier.start('Uploading');
      notifier.succeed('video-123', previewUrl: 'https://preview');
      expect(notifier.state.isUploading, isFalse);
      expect(notifier.state.progress, 1.0);
      expect(notifier.state.videoId, 'video-123');
      expect(notifier.state.previewUrl, 'https://preview');
      expect(notifier.state.statusText, 'Upload complete');
      expect(notifier.state.errorText, isNull);
    });

    test('fail() sets error state', () {
      notifier.start('Uploading');
      notifier.updateProgress(0.3);
      notifier.fail('Network error');
      expect(notifier.state.isUploading, isFalse);
      expect(notifier.state.errorText, 'Network error');
      expect(notifier.state.progress, 0.3); // preserves last progress
    });

    test('reset() returns to initial state', () {
      notifier.start('Uploading');
      notifier.updateProgress(0.5);
      notifier.reset();
      expect(notifier.state.isUploading, isFalse);
      expect(notifier.state.progress, 0.0);
      expect(notifier.state.statusText, '');
      expect(notifier.state.errorText, isNull);
      expect(notifier.state.videoId, isNull);
    });

    test('full lifecycle: start → progress → succeed', () {
      notifier.start('Preparing...');
      notifier.updateProgress(0.25, 'Uploading 25%');
      notifier.updateProgress(0.75, 'Uploading 75%');
      notifier.succeed('vid-abc');

      expect(notifier.state.isUploading, isFalse);
      expect(notifier.state.progress, 1.0);
      expect(notifier.state.videoId, 'vid-abc');
    });

    test('full lifecycle: start → progress → fail → reset', () {
      notifier.start('Preparing...');
      notifier.updateProgress(0.4);
      notifier.fail('Timeout');
      expect(notifier.state.errorText, 'Timeout');

      notifier.reset();
      expect(notifier.state.errorText, isNull);
      expect(notifier.state.isUploading, isFalse);
    });
  });
}
