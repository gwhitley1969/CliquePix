import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/paywall/domain/entitlement_state.dart';
import 'package:clique_pix/models/user_model.dart';

void main() {
  group('EntitlementState.fromJson', () {
    test('parses an active trial', () {
      final e = EntitlementState.fromJson(const {
        'active': false,
        'product_id': null,
        'period_type': null,
        'will_renew': null,
        'expires_at': null,
        'store': null,
        'in_trial': true,
        'trial_ends_at': '2026-06-15T00:00:00.000Z',
        'effective_active': true,
      });
      expect(e.active, false);
      expect(e.inTrial, true);
      expect(e.effectiveActive, true);
      expect(e.trialEndsAt, DateTime.parse('2026-06-15T00:00:00.000Z'));
    });

    test('parses an active subscriber', () {
      final e = EntitlementState.fromJson(const {
        'active': true,
        'product_id': 'plus_annual',
        'period_type': 'normal',
        'will_renew': true,
        'expires_at': '2027-06-01T00:00:00.000Z',
        'store': 'APP_STORE',
        'in_trial': false,
        'trial_ends_at': null,
        'effective_active': true,
      });
      expect(e.active, true);
      expect(e.effectiveActive, true);
      expect(e.productId, 'plus_annual');
      expect(e.store, 'APP_STORE');
    });
  });

  group('UserModel.entitlement', () {
    test('defaults to EntitlementState.none when entitlement is absent (old backend)', () {
      final u = UserModel.fromJson({
        'id': 'u1',
        'display_name': 'Test',
        'email_or_phone': 't@example.com',
        'created_at': '2026-06-01T00:00:00.000Z',
      });
      expect(u.entitlement.effectiveActive, false);
      expect(u.entitlement.inTrial, false);
    });

    test('parses the entitlement object when present', () {
      final u = UserModel.fromJson({
        'id': 'u1',
        'display_name': 'Test',
        'email_or_phone': 't@example.com',
        'created_at': '2026-06-01T00:00:00.000Z',
        'entitlement': {
          'active': false,
          'in_trial': true,
          'trial_ends_at': '2026-06-15T00:00:00.000Z',
          'effective_active': true,
        },
      });
      expect(u.entitlement.effectiveActive, true);
      expect(u.entitlement.inTrial, true);
    });

    test('round-trips entitlement through toJson (cached-user preservation)', () {
      final u = UserModel.fromJson({
        'id': 'u1',
        'display_name': 'Test',
        'email_or_phone': 't@example.com',
        'created_at': '2026-06-01T00:00:00.000Z',
        'entitlement': {
          'active': true,
          'in_trial': false,
          'effective_active': true,
          'product_id': 'plus_annual',
        },
      });
      final round = UserModel.fromJson(u.toJson());
      expect(round.entitlement.effectiveActive, true);
      expect(round.entitlement.active, true);
      expect(round.entitlement.productId, 'plus_annual');
    });
  });
}
