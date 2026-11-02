import 'package:go_router/go_router.dart';
import 'package:clique_pix/services/telemetry_service.dart';

/// Opens the subscribe flow from a trial prompt — the Home banner, the
/// Profile row, or the trial-ending push.
///
/// With access (still in trial) that's the dismissible `/subscribe` paywall,
/// pushed so Close returns to where the user was. Without access (the trial
/// already ended) the router would bounce `/subscribe` to `/paywall` anyway,
/// so go there directly rather than stacking a second paywall.
void openSubscribe(
  GoRouter router, {
  required bool hasAccess,
  required String source,
  required TelemetryService telemetry,
}) {
  telemetry.record('subscribe_entry_tapped',
      extra: {'source': source, 'has_access': '$hasAccess'});
  if (hasAccess) {
    router.push('/subscribe?source=$source');
  } else {
    router.go('/paywall');
  }
}
