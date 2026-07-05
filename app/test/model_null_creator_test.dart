import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/models/clique_model.dart';
import 'package:clique_pix/models/event_model.dart';
import 'package:clique_pix/models/photo_model.dart';
import 'package:clique_pix/models/video_model.dart';

/// Regression for the Z Fold 7 grey-screen crash (2026-06-16): a clique whose
/// creator account was deleted has `created_by_user_id = NULL` (FK SET NULL).
/// The non-null `as String` cast threw `Null is not a subtype of String`,
/// errored the cliques provider, and crashed the whole Home screen when
/// `cliquesAsync.value` rethrew it during build. The same latent bug existed
/// on events/photos/videos (uploader/creator deleted). These models must now
/// parse a null creator/uploader into '' instead of throwing.
void main() {
  group('null creator/uploader is tolerated (account-deletion SET NULL)', () {
    test('CliqueModel.fromJson with null created_by_user_id does not throw', () {
      final c = CliqueModel.fromJson(const {
        'id': '9525a0ea-5faa-428a-8404-9248a0646c07',
        'name': 'Orphaned Clique',
        'invite_code': 'abc123',
        'created_by_user_id': null,
        'member_count': 3,
        'created_at': '2026-06-01T00:00:00.000Z',
      });
      expect(c.createdByUserId, '');
      expect(c.createdByUserId == 'some-current-user-id', false);
    });

    test('EventModel.fromJson with null created_by_user_id does not throw', () {
      final e = EventModel.fromJson(const {
        'id': 'e1',
        'clique_id': 'c1',
        'name': 'Orphaned Event',
        'created_by_user_id': null,
        'retention_hours': 72,
        'status': 'active',
        'created_at': '2026-06-01T00:00:00.000Z',
        'expires_at': '2026-06-04T00:00:00.000Z',
      });
      expect(e.createdByUserId, '');
    });

    test('PhotoModel.fromJson with null uploaded_by_user_id does not throw', () {
      final p = PhotoModel.fromJson(const {
        'id': 'p1',
        'event_id': 'e1',
        'uploaded_by_user_id': null,
        'blob_path': 'photos/x.jpg',
        'status': 'active',
        'created_at': '2026-06-01T00:00:00.000Z',
        'expires_at': '2026-06-02T00:00:00.000Z',
      });
      expect(p.uploadedByUserId, '');
    });

    test('VideoModel.fromJson with null uploaded_by_user_id does not throw', () {
      final v = VideoModel.fromJson(const {
        'id': 'v1',
        'event_id': 'e1',
        'uploaded_by_user_id': null,
        'status': 'active',
        'processing_status': 'complete',
        'created_at': '2026-06-01T00:00:00.000Z',
        'expires_at': '2026-06-02T00:00:00.000Z',
      });
      expect(v.uploadedByUserId, '');
    });
  });
}
