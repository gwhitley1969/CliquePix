import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_constants.dart';

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService();
});

class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  GoRouter? _router;

  void initialize(GoRouter router) {
    _router = router;

    // Handle initial link (app opened from deep link)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    // Handle links while app is running
    _subscription = _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (uri.host != AppConstants.deepLinkHost) return;

    final path = uri.path;
    if (path.startsWith(AppConstants.invitePath)) {
      final inviteCode = path.substring(AppConstants.invitePath.length);
      if (inviteCode.isNotEmpty) {
        _router?.go('/invite/$inviteCode');
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
