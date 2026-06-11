// Regression tests for the entitlement-hardening PR (2026-06-05):
//   - markExpired must self-validate expiry (TOCTOU guard): only deactivate a
//     row whose stored expiry has genuinely passed, so a RENEWAL landing in the
//     reconciliation window can't deactivate a just-paid customer.
//   - upsertEntitlement must reject a non-UUID app_user_id BEFORE the DB UPDATE
//     (a non-UUID raises a Postgres uuid-cast error → webhook 500 → RC retry-storm).

const execMock = jest.fn();
const queryOneMock = jest.fn();

jest.mock('../shared/services/dbService', () => ({
  execute: (...args: unknown[]) => execMock(...args),
  query: jest.fn(),
  queryOne: (...args: unknown[]) => queryOneMock(...args),
}));

jest.mock('../shared/services/telemetryService', () => ({
  trackEvent: jest.fn(),
}));

import {
  markExpired,
  upsertEntitlement,
  type RcWebhookEvent,
} from '../shared/services/entitlementService';

beforeEach(() => {
  execMock.mockReset().mockResolvedValue(1);
  queryOneMock.mockReset();
});

describe('markExpired — TOCTOU self-validation', () => {
  it('re-checks expiry in the WHERE so a renewed payer is not deactivated', async () => {
    await markExpired('11111111-1111-1111-1111-111111111111');

    expect(execMock).toHaveBeenCalledTimes(1);
    const sql = String(execMock.mock.calls[0][0]);
    expect(sql).toContain('entitlement_active = TRUE');
    expect(sql).toContain('entitlement_expires_at IS NOT NULL');
    expect(sql).toContain('entitlement_expires_at < NOW()');
  });
});

describe('upsertEntitlement — non-UUID app_user_id guard', () => {
  function event(overrides: Partial<RcWebhookEvent> = {}): RcWebhookEvent {
    return {
      id: 'evt-1',
      type: 'INITIAL_PURCHASE',
      event_timestamp_ms: 1_000,
      app_user_id: '$RCAnonymousID:abc123',
      entitlement_ids: ['plus'],
      ...overrides,
    };
  }

  it('rejects a non-UUID app_user_id without touching the DB', async () => {
    const result = await upsertEntitlement(event());

    expect(result).toEqual({ applied: false, reason: 'invalid_user_id' });
    expect(execMock).not.toHaveBeenCalled(); // never reaches the UPDATE
  });

  it('rejects only when NO candidate id is a UUID', async () => {
    const result = await upsertEntitlement(
      event({
        app_user_id: '$RCAnonymousID:abc123',
        original_app_user_id: 'not-a-uuid',
        aliases: ['$RCAnonymousID:abc123', 'not-a-uuid'],
      }),
    );

    expect(result).toEqual({ applied: false, reason: 'invalid_user_id' });
    expect(execMock).not.toHaveBeenCalled();
  });

  it('proceeds to the UPDATE for a valid UUID app_user_id', async () => {
    const result = await upsertEntitlement(
      event({ app_user_id: '550e8400-e29b-41d4-a716-446655440000' }),
    );

    expect(execMock).toHaveBeenCalled();
    expect(result).toEqual({ applied: true, active: true });
  });

  // 2026-06-11 regression: RC pins original_app_user_id to the customer's
  // FIRST id — `$RCAnonymousID:...` forever for SDK-created customers, even
  // after Purchases.logIn aliases in our users.id. The old
  // `original_app_user_id ?? app_user_id` preference dropped EVERY webhook
  // for anonymous-origin customers (incl. the reviewer's promotional grant)
  // as invalid_user_id.
  it('prefers a UUID app_user_id over an anonymous original_app_user_id (promo-grant fix)', async () => {
    const result = await upsertEntitlement(
      event({
        type: 'NON_RENEWING_PURCHASE', // what a dashboard promo grant emits
        app_user_id: '325e4455-b1b8-461e-a844-6f158cffaf84',
        original_app_user_id: '$RCAnonymousID:wxYz9876',
        aliases: ['$RCAnonymousID:wxYz9876', '325e4455-b1b8-461e-a844-6f158cffaf84'],
      }),
    );

    expect(result).toEqual({ applied: true, active: true });
    // The UPDATE must target the identified users.id UUID ($1).
    expect(execMock.mock.calls[0][1][0]).toBe('325e4455-b1b8-461e-a844-6f158cffaf84');
  });

  it('falls back to a UUID alias when both primary ids are anonymous', async () => {
    const result = await upsertEntitlement(
      event({
        app_user_id: '$RCAnonymousID:abc123',
        original_app_user_id: '$RCAnonymousID:abc123',
        aliases: ['$RCAnonymousID:abc123', '550e8400-e29b-41d4-a716-446655440000'],
      }),
    );

    expect(result).toEqual({ applied: true, active: true });
    expect(execMock.mock.calls[0][1][0]).toBe('550e8400-e29b-41d4-a716-446655440000');
  });
});
