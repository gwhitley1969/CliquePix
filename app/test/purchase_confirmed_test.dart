// The post-purchase reconcile loop (OptimisticEntitlementNotifier) keeps the
// optimistic flag set until the backend confirms the purchase. It must wait
// for an actual subscription (`entitlement.active`), not effective access: a
// trial user buying from /subscribe already has effective access, so keying
// off effective_active would end the loop before the webhook/RC sync lands
// and briefly bring the trial banner back.

import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/auth/domain/auth_state.dart';
import 'package:clique_pix/features/paywall/presentation/paywall_providers.dart';
import 'package:clique_pix/models/user_model.dart';

AuthState _user(Map<String, dynamic> entitlement) =>
    AuthAuthenticated(UserModel.fromJson({
      'id': 'u1',
      'display_name': 'Test',
      'email_or_phone': 't@example.com',
      'created_at': '2026-06-01T00:00:00.000Z',
      'entitlement': entitlement,
    }));

void main() {
  test('a trial user with access is not yet a confirmed purchase', () {
    expect(
      isPurchaseConfirmed(_user({
        'active': false,
        'in_trial': true,
        'trial_ends_at': '2026-11-05T00:00:00.000Z',
        'effective_active': true,
      })),
      isFalse,
    );
  });

  test('an active subscription confirms the purchase', () {
    expect(
      isPurchaseConfirmed(_user({
        'active': true,
        'in_trial': true,
        'effective_active': true,
      })),
      isTrue,
    );
  });

  test('a lapsed user is not confirmed', () {
    expect(
      isPurchaseConfirmed(_user({
        'active': false,
        'in_trial': false,
        'effective_active': false,
      })),
      isFalse,
    );
  });

  test('a signed-out state is not confirmed', () {
    expect(isPurchaseConfirmed(const AuthUnauthenticated()), isFalse);
  });
}
