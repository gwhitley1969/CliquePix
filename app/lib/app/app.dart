import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/routing/app_router.dart';
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_providers.dart';

class CliquePix extends ConsumerStatefulWidget {
  const CliquePix({super.key});

  @override
  ConsumerState<CliquePix> createState() => _CliquePixState();
}

class _CliquePixState extends ConsumerState<CliquePix> {
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    final router = ref.read(routerProvider);
    ref.read(deepLinkServiceProvider).initialize(router);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final authState = ref.watch(authStateProvider);

    // Defer push init by one frame so the FCM permission UIAlertController is
    // presented after Safari (SFSafariViewController) has fully dismissed and
    // Flutter's view controller has re-attached to the UIWindow. Calling
    // initialize() synchronously inside build() right after Safari closes was
    // observed to terminate the app on iOS first-install.
    if (authState is AuthAuthenticated && !_pushInitialized) {
      _pushInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await ref.read(pushNotificationServiceProvider).initialize();
        } catch (e) {
          debugPrint('[CliquePix] Push init failed (non-fatal): $e');
        }
      });
    }

    return MaterialApp.router(
      title: 'Clique Pix',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
