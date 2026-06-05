// Regression test for the RC webhook retry-storm guard (2026-06-05): the handler
// must return 200 on ANY non-auth outcome (including an unexpected throw from
// upsertEntitlement, e.g. a DB error or a poison event). The pre-fix catch block
// called handleError() which returns 500 — contradicting the documented
// invariant and triggering RevenueCat's exponential-backoff retry-storm.

const authMock = jest.fn();
const upsertMock = jest.fn();

jest.mock('../shared/middleware/revenuecatAuthMiddleware', () => ({
  authenticateRevenueCatWebhook: (...args: unknown[]) => authMock(...args),
}));

jest.mock('../shared/services/entitlementService', () => ({
  upsertEntitlement: (...args: unknown[]) => upsertMock(...args),
}));

jest.mock('../shared/services/telemetryService', () => ({
  trackEvent: jest.fn(),
}));

import { revenuecatWebhook } from '../functions/revenuecatWebhook';
import { UnauthorizedError } from '../shared/utils/errors';

function mockReq(body: unknown) {
  return { json: async () => body } as never;
}
function mockCtx() {
  return { invocationId: 'inv-1', error: jest.fn(), warn: jest.fn() } as never;
}

const validEvent = {
  event: { id: 'e1', type: 'RENEWAL', app_user_id: '$RCAnonymousID:x', entitlement_ids: ['plus'] },
};

beforeEach(() => {
  authMock.mockReset().mockReturnValue(undefined); // auth passes by default
  upsertMock.mockReset();
});

describe('revenuecatWebhook — always-200-on-non-auth invariant', () => {
  it('returns 200 (not 500) when upsertEntitlement throws (DB error / poison event)', async () => {
    upsertMock.mockRejectedValue(new Error('invalid input syntax for type uuid'));

    const res = await revenuecatWebhook(mockReq(validEvent), mockCtx());

    expect(res.status).toBe(200);
  });

  it('returns 200 when upsert reports a non-UUID app_user_id (clean no-op)', async () => {
    upsertMock.mockResolvedValue({ applied: false, reason: 'invalid_user_id' });

    const res = await revenuecatWebhook(mockReq(validEvent), mockCtx());

    expect(res.status).toBe(200);
  });

  it('returns 200 when upsert applies normally', async () => {
    upsertMock.mockResolvedValue({ applied: true, active: true });

    const res = await revenuecatWebhook(mockReq(validEvent), mockCtx());

    expect(res.status).toBe(200);
  });

  it('returns 401 ONLY on auth failure', async () => {
    authMock.mockImplementation(() => {
      throw new UnauthorizedError('bad secret');
    });

    const res = await revenuecatWebhook(mockReq({}), mockCtx());

    expect(res.status).toBe(401);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  it('returns 200 on a malformed payload (missing event fields)', async () => {
    const res = await revenuecatWebhook(mockReq({ event: { id: 'e1' } }), mockCtx());

    expect(res.status).toBe(200);
    expect(upsertMock).not.toHaveBeenCalled();
  });
});
