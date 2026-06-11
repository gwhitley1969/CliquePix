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

  // A getter, NOT a captured GoRouter instance: the router is recreated on
  // identity change (see routerProvider), and a captured instance would go
  // stale — deep links tapped after a sign-out/sign-in would route on a
  // detached router and silently do nothing.
  GoRouter Function()? _getRouter;

  void initialize(GoRouter Function() getRouter) {
    _getRouter = getRouter;

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
        _getRouter?.call().go('/invite/$inviteCode');
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
