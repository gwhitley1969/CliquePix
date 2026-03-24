import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static String timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dateTime);
  }

  static String formatExpiry(DateTime expiresAt) {
    final now = DateTime.now();
    final diff = expiresAt.difference(now);

    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 1) return '${diff.inMinutes}m left';
    if (diff.inHours < 24) return '${diff.inHours}h left';
    return '${diff.inDays}d left';
  }

  static String formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
  }

  static bool isExpiringSoon(DateTime expiresAt) {
    return expiresAt.difference(DateTime.now()).inHours < 24;
  }
}
