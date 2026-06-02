import { buildEntitlementResponse, AuthUserRow } from '../shared/services/avatarEnricher';

// Minimal row factory — only the fields buildEntitlementResponse reads.
function row(overrides: Partial<AuthUserRow> = {}): AuthUserRow {
  return {
    id: 'u1',
    display_name: 'Test',
    email_or_phone: 't@example.com',
    avatar_blob_path: null,
    avatar_thumb_blob_path: null,
    avatar_updated_at: null,
    avatar_frame_preset: 0,
    avatar_prompt_dismissed: false,
    avatar_prompt_snoozed_until: null,
    created_at: new Date('2026-06-01T00:00:00Z'),
    ...overrides,
  };
}

const NOW = new Date('2026-06-10T00:00:00Z');

describe('buildEntitlementResponse — trial', () => {
  it('reports in_trial + effective_active when trial_ends_at is in the future', () => {
    const r = buildEntitlementResponse(
      row({ trial_ends_at: new Date('2026-06-15T00:00:00Z') }),
      NOW,
    );
    expect(r.in_trial).toBe(true);
    expect(r.effective_active).toBe(true);
    expect(r.active).toBe(false);
    expect(r.trial_ends_at).toBe('2026-06-15T00:00:00.000Z');
  });

  it('reports not-in-trial when trial_ends_at has passed and no subscription', () => {
    const r = buildEntitlementResponse(
      row({ trial_ends_at: new Date('2026-06-05T00:00:00Z') }),
      NOW,
    );
    expect(r.in_trial).toBe(false);
    expect(r.effective_active).toBe(false);
  });

  it('effective_active is true for an active subscriber even with an expired trial', () => {
    const r = buildEntitlementResponse(
      row({
        entitlement_active: true,
        trial_ends_at: new Date('2026-06-05T00:00:00Z'),
      }),
      NOW,
    );
    expect(r.active).toBe(true);
    expect(r.in_trial).toBe(false);
    expect(r.effective_active).toBe(true);
  });

  it('handles a null trial_ends_at (never stamped)', () => {
    const r = buildEntitlementResponse(row({ trial_ends_at: null }), NOW);
    expect(r.in_trial).toBe(false);
    expect(r.trial_ends_at).toBeNull();
    expect(r.effective_active).toBe(false);
  });
});

import { requireActiveEntitlement } from '../shared/middleware/requireActiveEntitlement';
import type { AuthenticatedUser } from '../shared/middleware/authMiddleware';
import { SubscriptionRequiredError } from '../shared/utils/errors';

// Minimal AuthenticatedUser — requireActiveEntitlement only reads two fields.
function authUser(overrides: Partial<AuthenticatedUser> = {}): AuthenticatedUser {
  return {
    id: 'u1',
    externalAuthId: 'ext1',
    displayName: 'Test',
    emailOrPhone: 't@example.com',
    avatarBlobPath: null,
    avatarThumbBlobPath: null,
    avatarUpdatedAt: null,
    avatarFramePreset: 0,
    entitlementActive: false,
    entitlementProductId: null,
    entitlementPeriodType: null,
    entitlementWillRenew: null,
    entitlementExpiresAt: null,
    entitlementStore: null,
    trialEndsAt: null,
    ...overrides,
  };
}

const NOW2 = new Date('2026-06-10T00:00:00Z');

describe('requireActiveEntitlement — trial', () => {
  it('passes a subscribed user', () => {
    expect(() =>
      requireActiveEntitlement(authUser({ entitlementActive: true }), NOW2),
    ).not.toThrow();
  });

  it('passes a user within the trial window', () => {
    expect(() =>
      requireActiveEntitlement(
        authUser({ trialEndsAt: new Date('2026-06-15T00:00:00Z') }),
        NOW2,
      ),
    ).not.toThrow();
  });

  it('throws for an unsubscribed user with an expired trial', () => {
    expect(() =>
      requireActiveEntitlement(
        authUser({ trialEndsAt: new Date('2026-06-05T00:00:00Z') }),
        NOW2,
      ),
    ).toThrow(SubscriptionRequiredError);
  });

  it('throws for an unsubscribed user with no trial stamped', () => {
    expect(() => requireActiveEntitlement(authUser(), NOW2)).toThrow(
      SubscriptionRequiredError,
    );
  });
});
