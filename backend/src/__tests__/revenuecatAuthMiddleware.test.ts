import { authenticateRevenueCatWebhook } from '../shared/middleware/revenuecatAuthMiddleware';
import { UnauthorizedError } from '../shared/utils/errors';

function reqWith(auth: string | null) {
  return {
    headers: { get: (k: string) => (k.toLowerCase() === 'authorization' ? auth : null) },
  } as never;
}

describe('authenticateRevenueCatWebhook', () => {
  const ORIG = process.env.REVENUECAT_WEBHOOK_SECRET;
  afterEach(() => {
    if (ORIG === undefined) delete process.env.REVENUECAT_WEBHOOK_SECRET;
    else process.env.REVENUECAT_WEBHOOK_SECRET = ORIG;
  });

  it('throws UnauthorizedError when no Authorization header', () => {
    process.env.REVENUECAT_WEBHOOK_SECRET = 'sekret';
    expect(() => authenticateRevenueCatWebhook(reqWith(null))).toThrow(UnauthorizedError);
  });

  it('throws UnauthorizedError on a wrong secret', () => {
    process.env.REVENUECAT_WEBHOOK_SECRET = 'sekret';
    expect(() => authenticateRevenueCatWebhook(reqWith('Bearer wrong'))).toThrow(UnauthorizedError);
  });

  it('passes on the correct secret', () => {
    process.env.REVENUECAT_WEBHOOK_SECRET = 'sekret';
    expect(() => authenticateRevenueCatWebhook(reqWith('Bearer sekret'))).not.toThrow();
  });

  it('throws UnauthorizedError (NOT a plain Error) when the secret env var is unset', () => {
    delete process.env.REVENUECAT_WEBHOOK_SECRET;
    // A provided header forces the getExpectedHeader path. Must be Unauthorized-
    // Error so the webhook surfaces a loud 401, not a silent always-200.
    expect(() => authenticateRevenueCatWebhook(reqWith('Bearer anything'))).toThrow(
      UnauthorizedError,
    );
  });
});
