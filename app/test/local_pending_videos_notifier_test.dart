import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/videos/domain/local_pending_video.dart';
import 'package:clique_pix/features/videos/presentation/videos_providers.dart';

void main() {
  late LocalPendingVideosNotifier notifier;

  LocalPendingVideo createVideo({
    String localTempId = 'vid-1',
    String eventId = 'event-1',
    UploadStage stage = UploadStage.localOnly,
    String? serverVideoId,
  }) {
    return LocalPendingVideo(
      localTempId: localTempId,
      eventId: eventId,
      localFilePath: '/tmp/$localTempId.mp4',
      durationSeconds: 30,
      createdAt: DateTime(2026, 4, 10),
      uploadStage: stage,
      serverVideoId: serverVideoId,
    );
  }

  setUp(() {
    notifier = LocalPendingVideosNotifier('event-1');
  });

  // ─── Initial state ───────────────────────────────────────────────────

  test('starts with empty list', () {
    expect(notifier.state, isEmpty);
  });

  // ─── add ─────────────────────────────────────────────────────────────

  group('add', () {
    test('adds a video to the list', () {
      final video = createVideo();
      notifier.add(video);
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.localTempId, 'vid-1');
    });

    test('appends multiple videos', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.add(createVideo(localTempId: 'b'));
      notifier.add(createVideo(localTempId: 'c'));
      expect(notifier.state, hasLength(3));
      expect(notifier.state.map((v) => v.localTempId), ['a', 'b', 'c']);
    });
  });

  // ─── updateStage ─────────────────────────────────────────────────────

  group('updateStage', () {
    test('updates stage for matching localTempId', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.uploading);
      expect(notifier.state.first.uploadStage, UploadStage.uploading);
    });

    test('does not modify other items', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.add(createVideo(localTempId: 'b'));
      notifier.updateStage('a', UploadStage.uploading);
      expect(notifier.state[1].uploadStage, UploadStage.localOnly);
    });

    test('sets progress', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.uploading, progress: 0.5);
      expect(notifier.state.first.uploadProgress, 0.5);
    });

    test('sets serverVideoId', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.processing, serverVideoId: 'sv-1');
      expect(notifier.state.first.serverVideoId, 'sv-1');
    });

    test('sets previewUrl', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.processing, previewUrl: 'https://preview');
      expect(notifier.state.first.previewUrl, 'https://preview');
    });

    test('sets errorMessage on failure', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.failed, errorMessage: 'Network error');
      expect(notifier.state.first.uploadStage, UploadStage.failed);
      expect(notifier.state.first.errorMessage, 'Network error');
    });

    test('no-op for non-matching id', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('nonexistent', UploadStage.uploading);
      expect(notifier.state.first.uploadStage, UploadStage.localOnly);
    });
  });

  // ─── reconcileComplete ───────────────────────────────────────────────

  group('reconcileComplete', () {
    test('marks matching serverVideoId as complete', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.processing, serverVideoId: 'sv-1');
      notifier.reconcileComplete('sv-1');
      expect(notifier.state.first.uploadStage, UploadStage.complete);
    });

    test('does not modify items with different serverVideoId', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.add(createVideo(localTempId: 'b'));
      notifier.updateStage('a', UploadStage.processing, serverVideoId: 'sv-1');
      notifier.updateStage('b', UploadStage.processing, serverVideoId: 'sv-2');
      notifier.reconcileComplete('sv-1');
      expect(notifier.state[0].uploadStage, UploadStage.complete);
      expect(notifier.state[1].uploadStage, UploadStage.processing);
    });

    test('no-op for non-matching serverVideoId', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.updateStage('a', UploadStage.processing, serverVideoId: 'sv-1');
      notifier.reconcileComplete('sv-999');
      expect(notifier.state.first.uploadStage, UploadStage.processing);
    });
  });

  // ─── remove ──────────────────────────────────────────────────────────

  group('remove', () {
    test('removes item by localTempId', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.add(createVideo(localTempId: 'b'));
      notifier.remove('a');
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.localTempId, 'b');
    });

    test('no-op for non-matching id', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.remove('nonexistent');
      expect(notifier.state, hasLength(1));
    });

    test('removing last item leaves empty list', () {
      notifier.add(createVideo(localTempId: 'a'));
      notifier.remove('a');
      expect(notifier.state, isEmpty);
    });
  });

  // ─── Full lifecycle ──────────────────────────────────────────────────

  group('full lifecycle', () {
    test('create → upload → commit → process → reconcile', () {
      final video = createVideo(localTempId: 'lifecycle-1');
      notifier.add(video);
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.uploadStage, UploadStage.localOnly);

      notifier.updateStage('lifecycle-1', UploadStage.uploading, progress: 0.1);
      notifier.updateStage('lifecycle-1', UploadStage.uploading, progress: 0.9);
      notifier.updateStage('lifecycle-1', UploadStage.committing, progress: 0.95);
      notifier.updateStage(
        'lifecycle-1',
        UploadStage.processing,
        serverVideoId: 'server-vid',
        previewUrl: 'https://blob/preview',
      );

      final processing = notifier.state.first;
      expect(processing.uploadStage, UploadStage.processing);
      expect(processing.serverVideoId, 'server-vid');
      expect(processing.previewUrl, 'https://blob/preview');

      notifier.reconcileComplete('server-vid');
      expect(notifier.state.first.uploadStage, UploadStage.complete);
    });
  });
}
