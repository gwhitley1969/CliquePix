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

  it('rejects when the RESOLVED id (original_app_user_id) is a non-UUID', async () => {
    const result = await upsertEntitlement(
      event({
        app_user_id: '550e8400-e29b-41d4-a716-446655440000',
        original_app_user_id: 'not-a-uuid',
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
});
