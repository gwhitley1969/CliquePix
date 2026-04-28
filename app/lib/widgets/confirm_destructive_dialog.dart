import 'package:flutter/material.dart';

/// Shared dark-theme destructive-action confirmation dialog.
///
/// Styling is lifted verbatim from the canonical version in
/// `event_detail_screen.dart` so every destructive confirm in the app
/// (event delete, leave clique, delete clique, remove member, delete
/// account, delete photo, delete video) renders identically.
///
/// Returns `true` when the user confirms, `false` otherwise (including
/// dismiss via back gesture or tap-outside).
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2035),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        body,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Title/body strings for media (photo/video) deletion confirmation.
/// Two flavors:
///   - Self-uploader → straightforward `Delete X?` / `This X will be permanently deleted.`
///   - Organizer removing someone else's media → `Remove X?` / wording that
///     emphasises the moderation action ("permanently deleted for everyone").
///
/// Centralised here so the menu (`media_owner_menu.dart`), photo detail
/// screen, and video player screen can't drift.
({String title, String body, String confirmLabel}) deleteDialogCopy({
  required String mediaLabel,
  required bool isOrganizerDeletingOthers,
}) {
  final lower = mediaLabel.toLowerCase();
  if (isOrganizerDeletingOthers) {
    return (
      title: 'Remove $mediaLabel?',
      body:
          "You're removing this $lower. It will be permanently deleted for everyone in this event.",
      confirmLabel: 'Remove',
    );
  }
  return (
    title: 'Delete $mediaLabel?',
    body: 'This $lower will be permanently deleted.',
    confirmLabel: 'Delete',
  );
}
