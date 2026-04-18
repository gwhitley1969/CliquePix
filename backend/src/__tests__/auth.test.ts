import {
  decideAgeGate,
  extractDobFromClaims,
  parseAnyDob,
} from '../functions/auth';

// ─── extractDobFromClaims ──────────────────────────────────────────────

describe('extractDobFromClaims', () => {
  it('reads a plain dateOfBirth claim', () => {
    expect(extractDobFromClaims({ dateOfBirth: '1990-05-15' })).toBe(
      '1990-05-15',
    );
  });

  it('reads a GUID-prefixed directory-schema-extension claim', () => {
    expect(
      extractDobFromClaims({
        extension_abc123def456_dateOfBirth: '1990-05-15',
      }),
    ).toBe('1990-05-15');
  });

  it('is case-insensitive on key', () => {
    expect(
      extractDobFromClaims({ extension_x_DateOfBirth: '1990-05-15' }),
    ).toBe('1990-05-15');
  });

  it('returns null when claim is absent', () => {
    expect(extractDobFromClaims({ sub: 'abc', email: 'a@b.c' })).toBeNull();
  });

  it('returns null for empty string values', () => {
    expect(extractDobFromClaims({ dateOfBirth: '   ' })).toBeNull();
  });
});

// ─── parseAnyDob ───────────────────────────────────────────────────────

describe('parseAnyDob', () => {
  it('parses YYYY-MM-DD', () => {
    const d = parseAnyDob('1990-05-15');
    expect(d).not.toBeNull();
    expect(d!.getUTCFullYear()).toBe(1990);
  });

  it('parses MM/DD/YYYY', () => {
    const d = parseAnyDob('05/15/1990');
    expect(d).not.toBeNull();
    expect(d!.getUTCFullYear()).toBe(1990);
    expect(d!.getUTCMonth()).toBe(4);
  });

  it('parses MMDDYYYY (no separators)', () => {
    const d = parseAnyDob('05151990');
    expect(d).not.toBeNull();
    expect(d!.getUTCFullYear()).toBe(1990);
  });

  it('returns null for garbage', () => {
    expect(parseAnyDob('not a date')).toBeNull();
    expect(parseAnyDob('')).toBeNull();
  });
});

// ─── decideAgeGate ─────────────────────────────────────────────────────

describe('decideAgeGate', () => {
  const now = new Date('2026-04-18T00:00:00Z');

  it('passes ≥13', () => {
    const result = decideAgeGate({ dateOfBirth: '1990-05-15' }, now);
    expect(result.action).toBe('pass');
    if (result.action === 'pass') expect(result.age).toBe(35);
  });

  it('blocks <13', () => {
    const result = decideAgeGate({ dateOfBirth: '2020-01-01' }, now);
    expect(result.action).toBe('block');
    if (result.action === 'block') expect(result.reason).toBe('under_13');
  });

  it('blocks exactly-12 (birthday not yet passed this year)', () => {
    // Born 2013-12-31 → on 2026-04-18 they are 12 years old
    const result = decideAgeGate({ dateOfBirth: '2013-12-31' }, now);
    expect(result.action).toBe('block');
  });

  it('passes exactly-13 on their birthday', () => {
    // Born 2013-04-18 → on 2026-04-18 they turn 13 today
    const result = decideAgeGate({ dateOfBirth: '2013-04-18' }, now);
    expect(result.action).toBe('pass');
    if (result.action === 'pass') expect(result.age).toBe(13);
  });

  it('grandfathers when DOB claim is missing', () => {
    const result = decideAgeGate({ sub: 'abc' }, now);
    expect(result.action).toBe('grandfather');
    if (result.action === 'grandfather')
      expect(result.reason).toBe('missing_claim');
  });

  it('grandfathers when DOB claim is unparseable', () => {
    const result = decideAgeGate({ dateOfBirth: 'bogus' }, now);
    expect(result.action).toBe('grandfather');
    if (result.action === 'grandfather')
      expect(result.reason).toBe('unparseable_dob');
  });

  it('handles GUID-prefixed claim name (real Entra shape)', () => {
    const result = decideAgeGate(
      { extension_abc123_dateOfBirth: '1990-05-15', sub: 'abc' },
      now,
    );
    expect(result.action).toBe('pass');
  });
});
