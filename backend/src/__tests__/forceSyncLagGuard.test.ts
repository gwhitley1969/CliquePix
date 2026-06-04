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
  fetchSubscriberFromRc: (...args: unknown[]) => fetchSubscriberMock(...args),
}));

import { forceSyncFromRcApi } from '../shared/services/entitlementService';

const FUTURE = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // +7 days
const PAST = new Date(Date.now() - 24 * 60 * 60 * 1000); // -1 day

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

// RC subscriber object with NO active plus entitlement (the lagging read).
function inactiveSubscriber() {
  return {
    subscriber: {
      entitlements: {}, // no 'plus' → isActive=false
      subscriptions: {},
    },
  };
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
