import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/videos/domain/local_pending_video.dart';

void main() {
  LocalPendingVideo createTestVideo({
    String localTempId = 'test-id',
    String eventId = 'event-1',
    String localFilePath = '/tmp/video.mp4',
    int durationSeconds = 30,
    UploadStage uploadStage = UploadStage.localOnly,
    double uploadProgress = 0.0,
    String? serverVideoId,
    String? previewUrl,
    String? errorMessage,
  }) {
    return LocalPendingVideo(
      localTempId: localTempId,
      eventId: eventId,
      localFilePath: localFilePath,
      durationSeconds: durationSeconds,
      createdAt: DateTime(2026, 4, 10),
      uploadStage: uploadStage,
      uploadProgress: uploadProgress,
      serverVideoId: serverVideoId,
      previewUrl: previewUrl,
      errorMessage: errorMessage,
    );
  }

  // ─── Construction ────────────────────────────────────────────────────

  group('LocalPendingVideo construction', () {
    test('defaults to localOnly stage and zero progress', () {
      final video = createTestVideo();
      expect(video.uploadStage, UploadStage.localOnly);
      expect(video.uploadProgress, 0.0);
      expect(video.serverVideoId, isNull);
      expect(video.previewUrl, isNull);
      expect(video.errorMessage, isNull);
    });

    test('stores all required fields', () {
      final video = createTestVideo(
        localTempId: 'abc-123',
        eventId: 'evt-456',
        localFilePath: '/data/v.mov',
        durationSeconds: 120,
      );
      expect(video.localTempId, 'abc-123');
      expect(video.eventId, 'evt-456');
      expect(video.localFilePath, '/data/v.mov');
      expect(video.durationSeconds, 120);
    });

    test('stores optional fields', () {
      final video = createTestVideo();
      expect(video.width, isNull);
      expect(video.height, isNull);
      expect(video.fileSizeBytes, isNull);
    });
  });

  // ─── copyWith ────────────────────────────────────────────────────────

  group('copyWith', () {
    test('changes uploadStage while preserving other fields', () {
      final original = createTestVideo();
      final updated = original.copyWith(uploadStage: UploadStage.uploading);
      expect(updated.uploadStage, UploadStage.uploading);
      expect(updated.localTempId, original.localTempId);
      expect(updated.eventId, original.eventId);
      expect(updated.localFilePath, original.localFilePath);
    });

    test('changes uploadProgress', () {
      final video = createTestVideo().copyWith(uploadProgress: 0.75);
      expect(video.uploadProgress, 0.75);
    });

    test('sets serverVideoId', () {
      final video = createTestVideo().copyWith(serverVideoId: 'server-vid-1');
      expect(video.serverVideoId, 'server-vid-1');
    });

    test('sets previewUrl', () {
      final video = createTestVideo().copyWith(previewUrl: 'https://blob.azure/preview');
      expect(video.previewUrl, 'https://blob.azure/preview');
    });

    test('sets errorMessage', () {
      final video = createTestVideo().copyWith(errorMessage: 'Upload failed');
      expect(video.errorMessage, 'Upload failed');
    });

    test('clears errorMessage with null', () {
      final withError = createTestVideo(errorMessage: 'Error');
      final cleared = withError.copyWith(errorMessage: null);
      expect(cleared.errorMessage, isNull);
    });

    test('preserves serverVideoId when not specified', () {
      final video = createTestVideo(serverVideoId: 'vid-1');
      final updated = video.copyWith(uploadStage: UploadStage.processing);
      expect(updated.serverVideoId, 'vid-1');
    });
  });

  // ─── durationLabel ───────────────────────────────────────────────────

  group('durationLabel', () {
    test('formats zero seconds', () {
      expect(createTestVideo(durationSeconds: 0).durationLabel, '0:00');
    });

    test('formats 30 seconds', () {
      expect(createTestVideo(durationSeconds: 30).durationLabel, '0:30');
    });

    test('formats 1 minute', () {
      expect(createTestVideo(durationSeconds: 60).durationLabel, '1:00');
    });

    test('formats 1 minute 5 seconds with padding', () {
      expect(createTestVideo(durationSeconds: 65).durationLabel, '1:05');
    });

    test('formats 5 minutes', () {
      expect(createTestVideo(durationSeconds: 300).durationLabel, '5:00');
    });

    test('formats 2 minutes 45 seconds', () {
      expect(createTestVideo(durationSeconds: 165).durationLabel, '2:45');
    });
  });

  // ─── generateId ──────────────────────────────────────────────────────

  group('generateId', () {
    test('returns a non-empty string', () {
      expect(LocalPendingVideo.generateId(), isNotEmpty);
    });

    test('returns unique values', () {
      final id1 = LocalPendingVideo.generateId();
      final id2 = LocalPendingVideo.generateId();
      expect(id1, isNot(equals(id2)));
    });

    test('returns UUID-formatted string', () {
      final id = LocalPendingVideo.generateId();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id),
        isTrue,
      );
    });
  });

  // ─── Upload stage lifecycle ──────────────────────────────────────────

  group('upload stage lifecycle', () {
    test('full success lifecycle: localOnly → uploading → committing → processing → complete', () {
      var video = createTestVideo();
      expect(video.uploadStage, UploadStage.localOnly);

      video = video.copyWith(uploadStage: UploadStage.uploading, uploadProgress: 0.1);
      expect(video.uploadStage, UploadStage.uploading);

      video = video.copyWith(uploadStage: UploadStage.committing, uploadProgress: 0.95);
      expect(video.uploadStage, UploadStage.committing);

      video = video.copyWith(
        uploadStage: UploadStage.processing,
        serverVideoId: 'server-1',
        previewUrl: 'https://blob/preview',
      );
      expect(video.uploadStage, UploadStage.processing);
      expect(video.serverVideoId, 'server-1');

      video = video.copyWith(uploadStage: UploadStage.complete);
      expect(video.uploadStage, UploadStage.complete);
    });

    test('failure lifecycle: localOnly → uploading → failed', () {
      var video = createTestVideo();
      video = video.copyWith(uploadStage: UploadStage.uploading);
      video = video.copyWith(
        uploadStage: UploadStage.failed,
        errorMessage: 'Network error',
      );
      expect(video.uploadStage, UploadStage.failed);
      expect(video.errorMessage, 'Network error');
    });
  });
}
