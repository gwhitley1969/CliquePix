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
