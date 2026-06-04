import { generateInviteCode, INVITE_CODE_MAX_LENGTH } from '../functions/cliques';
import { validateRequiredString, sanitizeString } from '../shared/utils/validators';

// Regression guard for the C1-hardening join break: generateInviteCode() was
// lengthened to 32 hex chars but joinClique still validated with maxLength 20,
// so sanitizeString() truncated every new code and the exact-match lookup 404'd.
// These tests pin the contract that the generated code survives the join-side
// validation byte-for-byte.

describe('invite code generate -> join round-trip', () => {
  it('generates a hex code that fits within INVITE_CODE_MAX_LENGTH', () => {
    const code = generateInviteCode();
    expect(code).toMatch(/^[0-9a-f]+$/);
    expect(code.length).toBe(32); // crypto.randomBytes(16).toString('hex')
    expect(code.length).toBeLessThanOrEqual(INVITE_CODE_MAX_LENGTH);
  });

  it('join-side validation preserves a freshly generated code unchanged', () => {
    for (let i = 0; i < 50; i++) {
      const code = generateInviteCode();
      // Exactly the call joinClique makes:
      const validated = validateRequiredString(code, 'invite_code', INVITE_CODE_MAX_LENGTH);
      expect(validated).toBe(code);
    }
  });

  it('still accepts (does not truncate) a legacy 8-char code', () => {
    const legacy = 'deadbeef';
    expect(validateRequiredString(legacy, 'invite_code', INVITE_CODE_MAX_LENGTH)).toBe(legacy);
  });

  it('demonstrates the old maxLength=20 would have truncated a 32-char code (the bug)', () => {
    const code = generateInviteCode();
    expect(sanitizeString(code, 20)).not.toBe(code);
    expect(sanitizeString(code, 20).length).toBe(20);
  });
});
