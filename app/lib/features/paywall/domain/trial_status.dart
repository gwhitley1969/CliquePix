import 'package:flutter/foundation.dart';
import 'entitlement_state.dart';

/// Time left in the app-granted free trial, as shown by the in-trial
/// subscribe prompts (Home banner, Profile row). Prices are deliberately
/// absent: they vary by storefront, and the paywall shows the localized ones.
@immutable
class TrialStatus {
  const TrialStatus(this.remaining);

  final Duration remaining;

  /// Whole days left, rounded up — a fresh 7-day trial reads "7 days".
  /// Only meaningful when [remaining] is at least one day.
  int get _daysLeft => (remaining.inMinutes / Duration.minutesPerDay).ceil();

  bool get _underADay => remaining < const Duration(days: 1);

  bool get _underAnHour => remaining < const Duration(hours: 1);

  static String _plural(int n, String unit) => n == 1 ? '1 $unit' : '$n ${unit}s';

  /// Full sentence for the Home banner.
  String get headline {
    if (_underAnHour) return 'Your free trial ends in less than an hour';
    if (_underADay) {
      return 'Your free trial ends in ${_plural(remaining.inHours, 'hour')}';
    }
    return '${_plural(_daysLeft, 'day')} left in your free trial';
  }

  /// Compact form for the Profile row subtitle.
  String get shortLabel {
    if (_underAnHour) return 'Free trial: less than an hour left';
    if (_underADay) return 'Free trial: ${_plural(remaining.inHours, 'hour')} left';
    return 'Free trial: ${_plural(_daysLeft, 'day')} left';
  }
}

/// Null when there's nothing to prompt: already subscribed, a purchase is
/// still confirming ([purchasePending] = the optimistic post-purchase flag),
/// or no unexpired trial.
TrialStatus? computeTrialStatus(
  EntitlementState entitlement, {
  required bool purchasePending,
  required DateTime now,
}) {
  if (entitlement.active || purchasePending) return null;
  final endsAt = entitlement.trialEndsAt;
  if (endsAt == null || !endsAt.isAfter(now)) return null;
  return TrialStatus(endsAt.difference(now));
}
