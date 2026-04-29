import 'package:dio/dio.dart';

/// Map a thrown error from a Dio call into a single human-readable line for
/// display via `AppErrorWidget` (or any other error UI). Never returns the
/// raw `DioException` toString.
///
/// Used by destination screens reachable from notification taps
/// (`PhotoDetailScreen`, `EventDetailScreen`, `CliqueDetailScreen`) where a
/// stale notification can race with an organizer / uploader / sole-owner
/// delete and produce a 404. A backend sweep cleans most of these up within
/// 15 min, but a freshly-deleted target between push and tap still needs a
/// human-friendly fallback at the screen layer.
///
/// Other screens that fetch resources by ID may benefit from this too — the
/// notifications-only sweep above is intentionally conservative for now.
String friendlyApiErrorMessage(Object err, {required String resourceLabel}) {
  if (err is DioException) {
    final code = err.response?.statusCode;
    if (code == 404) {
      return 'This $resourceLabel is no longer available. It may have been deleted or expired.';
    }
    if (code == 401 || code == 403) {
      return "You don't have access to this $resourceLabel.";
    }
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return "Couldn't reach Clique Pix. Check your connection and try again.";
    }
    if (code != null && code >= 500) {
      return 'Something went wrong on our end. Please try again in a moment.';
    }
  }
  return "Couldn't load this $resourceLabel. Please try again.";
}

/// True only for permanently-unrecoverable errors. Callers use this to decide
/// whether to render a "Go Back" button (404 — retry won't help) vs a
/// "Try Again" button (transient — retry might).
bool isPermanentlyGone(Object err) {
  return err is DioException && err.response?.statusCode == 404;
}
