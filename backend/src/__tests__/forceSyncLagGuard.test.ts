// Regression test for H1 (security audit 2026-06-04): forceSyncFromRcApi must
// NOT deactivate a just-paid subscriber off a stale RC API read. RC's REST API
// is eventually-consistent and lags webhooks by seconds–minutes — exactly the
// window when the client's 30s post-purchase auto-recovery calls this. If our
// DB already shows active + future expiry (a RENEWAL webhook we processed),
// the sync must leave that state alone instead of synthesizing an EXPIRATION
// that wins the ordering guard and makes the real webhook get rejected as stale.

const execMock = jest.fn();
const queryOneMock = jest.fn();
const fetchSubscriberMock = jest.fn();

jest.mock('../shared/services/dbService', () => ({
  execute: (...args: unknown[]) => execMock(...args),
  query: jest.fn(),
  queryOne: (...args: unknown[]) => queryOneMock(...args),
}));

jest.mock('../shared/services/telemetryService', () => ({
  trackEvent: jest.fn(),
}));

jest.mock('../shared/services/revenuecatRestClient', () => ({
  fetchPlusStateFromRc: (...args: unknown[]) => fetchSubscriberMock(...args),
}));

import { forceSyncFromRcApi } from '../shared/services/entitlementService';

const FUTURE = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // +7 days
const PAST = new Date(Date.now() - 24 * 60 * 60 * 1000); // -1 day
// forceSyncFromRcApi feeds userId into upsertEntitlement's synthetic event,
// which validates it is a UUID — use a real UUID for the active-path tests.
const REVIEWER_ID = '550e8400-e29b-41d4-a716-446655440000';

// A getEntitlement() row shape (snake_case columns queryOne returns).
function dbRow(overrides: Record<string, unknown> = {}) {
  return {
    entitlement_active: false,
    entitlement_product_id: null,
    entitlement_period_type: null,
    entitlement_will_renew: null,
    entitlement_expires_at: null,
    entitlement_store: null,
    entitlement_last_event_id: null,
    entitlement_updated_at: null,
    ...overrides,
  };
}

// RcPlusState shapes (the v2 client's distilled return value — see
// revenuecatRestClient.fetchPlusStateFromRc).

// NO active plus entitlement (the lagging read).
function inactiveSubscriber() {
  return { active: false, expiresAtMs: null, productId: null, store: null };
}

// Lifetime/promotional plus: no end date = never expires (the reviewer +
// beta-tester grant mechanism).
function lifetimePlusSubscriber() {
  return { active: true, expiresAtMs: null, productId: null, store: 'promotional' };
}

// Plus whose expiry is in the PAST (lapsed). The v2 client filters on
// gives_access so RC would normally report this as inactive already, but the
// service must also defend against a stale `active` + past end date.
function expiredPlusSubscriber() {
  return { active: true, expiresAtMs: PAST.getTime(), productId: 'plus_annual', store: 'app_store' };
}

beforeEach(() => {
  execMock.mockReset().mockResolvedValue(1);
  queryOneMock.mockReset();
  fetchSubscriberMock.mockReset();
});

describe('forceSyncFromRcApi — RC API-lag corroboration (H1)', () => {
  it('does NOT deactivate when DB shows active + future expiry but RC API lags inactive', async () => {
    fetchSubscriberMock.mockResolvedValue(inactiveSubscriber());
    // getEntitlement() → DB believes the user is active until a future date.
    queryOneMock.mockResolvedValue(
      dbRow({ entitlement_active: true, entitlement_expires_at: FUTURE }),
    );

    const result = await forceSyncFromRcApi('user-1');

    // No UPDATE (markExpired / synthetic upsert) should have fired.
    expect(execMock).not.toHaveBeenCalled();
    // Returns the existing active entitlement, not a deactivated one.
    expect(result?.active).toBe(true);
  });

  it('DOES deactivate when DB also shows expired (genuine expiry, no lag)', async () => {
    fetchSubscriberMock.mockResolvedValue(inactiveSubscriber());
    queryOneMock.mockResolvedValue(
      dbRow({ entitlement_active: true, entitlement_expires_at: PAST }),
    );

    await forceSyncFromRcApi('user-1');

    // markExpired runs an UPDATE — at least one execute call expected.
    expect(execMock).toHaveBeenCalled();
  });

  it('DOES deactivate when DB shows no active entitlement at all', async () => {
    fetchSubscriberMock.mockResolvedValue(inactiveSubscriber());
    queryOneMock.mockResolvedValue(dbRow({ entitlement_active: false }));

    await forceSyncFromRcApi('user-1');

    expect(execMock).toHaveBeenCalled();
  });
});

describe('forceSyncFromRcApi — lifetime/promotional grants (reviewer-lockout fix)', () => {
  // markExpired is the ONLY UPDATE that sets `entitlement_active = FALSE`; the
  // synthetic-RENEWAL upsert uses `entitlement_active          = $3`. So this
  // distinguishes "deactivated" from "kept active" in the execute mock.
  const calledMarkExpired = () =>
    execMock.mock.calls.some((c) => String(c[0]).includes('entitlement_active = FALSE'));

  it('keeps a lifetime/promotional plus (null expires_date) ACTIVE — never markExpired', async () => {
    fetchSubscriberMock.mockResolvedValue(lifetimePlusSubscriber());
    queryOneMock.mockResolvedValue(
      dbRow({ entitlement_active: true, entitlement_expires_at: null }),
    );

    const result = await forceSyncFromRcApi(REVIEWER_ID);

    // Takes the ACTIVE branch (synthetic RENEWAL upsert), NOT markExpired.
    expect(execMock).toHaveBeenCalled();
    expect(calledMarkExpired()).toBe(false);
    expect(result?.active).toBe(true);
  });

  it('still deactivates a plus whose expiry is genuinely in the PAST', async () => {
    fetchSubscriberMock.mockResolvedValue(expiredPlusSubscriber());
    queryOneMock.mockResolvedValue(
      dbRow({ entitlement_active: true, entitlement_expires_at: PAST }),
    );

    await forceSyncFromRcApi('user-1');

    expect(calledMarkExpired()).toBe(true);
  });

  it('does NOT deactivate an active promo (DB null expiry) when RC API lags with no plus', async () => {
    fetchSubscriberMock.mockResolvedValue(inactiveSubscriber()); // no plus → isActive=false
    queryOneMock.mockResolvedValue(
      dbRow({ entitlement_active: true, entitlement_expires_at: null }),
    );

    const result = await forceSyncFromRcApi(REVIEWER_ID);

    // Lag-guard now protects active + null expiry → no markExpired, no upsert.
    expect(execMock).not.toHaveBeenCalled();
    expect(result?.active).toBe(true);
  });
});
