import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'confirm_destructive_dialog.dart';

/// Card-header 3-dot menu for deleting a photo or video.
///
/// Renders nothing unless the current user is allowed to delete the media
/// AND the feed is not in multi-select (download) mode. Authorization is
/// computed by the parent: the uploader OR the event organizer
/// (`events.created_by_user_id`) is allowed; everyone else sees no menu.
///
/// When tapped, opens a popup with a single Delete action; confirmation
/// runs through [confirmDestructive] using copy from [deleteDialogCopy];
/// on confirm, the parent's [onDelete] callback is awaited.
///
/// Error mapping for the post-delete SnackBar is done by
/// [_deleteErrorMessage] — it reads the Azure Functions error envelope
/// (`e.response.data['error']['code']`) and maps canonical codes to
/// friendly strings. 404 is treated as success (already removed);
/// parent's invalidation has already run before the throw bubbles here.
class MediaOwnerMenu extends StatelessWidget {
  /// Human-readable label for dialog + SnackBar copy. Use `'Photo'` or
  /// `'Video'` — capitalized for titles, downcased inline in messages.
  final String mediaLabel;

  /// Whether the current user is allowed to delete this media (uploader
  /// OR event organizer). Computed by parent.
  final bool canDelete;

  /// True when the deleting user is the event organizer acting on
  /// someone else's media (moderation). Drives differentiated dialog
  /// + SnackBar copy via [deleteDialogCopy]. False for self-uploader
  /// deletes (uploader takes precedence).
  final bool isOrganizerDeletingOthers;

  /// Hide the menu while the feed is in multi-select download mode
  /// so the 3-dot tap target can't be confused with a selection tap.
  final bool isSelecting;

  /// Parent-supplied delete action. Typically:
  ///   await repo.deleteMedia(id);
  ///   ref.invalidate(eventMediaProvider(eventId));
  ///   (plus any media-type-specific cleanup)
  final Future<void> Function() onDelete;

  const MediaOwnerMenu({
    super.key,
    required this.mediaLabel,
    required this.canDelete,
    required this.isSelecting,
    required this.onDelete,
    this.isOrganizerDeletingOthers = false,
  });

  Future<void> _handleSelect(BuildContext context, String value) async {
    if (value != 'delete') return;
    final copy = deleteDialogCopy(
      mediaLabel: mediaLabel,
      isOrganizerDeletingOthers: isOrganizerDeletingOthers,
    );
    final confirmed = await confirmDestructive(
      context,
      title: copy.title,
      body: copy.body,
      confirmLabel: copy.confirmLabel,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await onDelete();
      if (!context.mounted) return;
      final successWord = isOrganizerDeletingOthers ? 'removed' : 'deleted';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$mediaLabel $successWord')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_deleteErrorMessage(e, mediaLabel))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canDelete || isSelecting) return const SizedBox.shrink();
    final menuLabel = isOrganizerDeletingOthers ? 'Remove' : 'Delete';
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: Colors.white.withValues(alpha: 0.6),
        size: 20,
      ),
      tooltip: '$mediaLabel actions',
      color: const Color(0xFF1A2035),
      padding: EdgeInsets.zero,
      onSelected: (v) => _handleSelect(context, v),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, color: Color(0xFFEF4444)),
              const SizedBox(width: 12),
              Text(menuLabel, style: const TextStyle(color: Color(0xFFEF4444))),
            ],
          ),
        ),
      ],
    );
  }
}

/// Maps a delete-call failure to a user-facing SnackBar message.
///
/// Reads the backend error code from the Azure Functions response envelope
/// (`{ data: null, error: { code, message, request_id } }`). Mirrors the
/// `_friendlyError` pattern used in `video_upload_screen.dart` and
/// `camera_capture_screen.dart`.
///
/// Notes:
///   - 404 is shown as "already removed" because the feed has already been
///     invalidated by the caller before this catch runs — the UI reflects
///     success even though the DELETE itself returned 404.
///   - 403 should never reach the user because the menu is gated by
///     `canDelete`; the handler is here as defense in depth.
String _deleteErrorMessage(Object e, String label) {
  final noun = label.toLowerCase();
  if (e is DioException) {
    final code = _extractErrorCode(e);
    if (code == 'FORBIDDEN') {
      return "You don't have permission to delete this $noun.";
    }
    if (code == 'PHOTO_NOT_FOUND' || code == 'VIDEO_NOT_FOUND') {
      return '$label already removed.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Network timeout. Try again.';
    }
  }
  return 'Failed to delete. Try again.';
}

/// Pulls the canonical backend error code out of the Azure Functions error
/// envelope: `{ data: null, error: { code, message, request_id } }`.
/// Returns null if the response body is missing, not a Map, or doesn't
/// follow the envelope shape.
String? _extractErrorCode(DioException e) {
  final data = e.response?.data;
  if (data is! Map) return null;
  final error = data['error'];
  if (error is! Map) return null;
  final code = error['code'];
  return code is String ? code : null;
}
