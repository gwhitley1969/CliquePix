import {
  MIN_AGE,
  parseDob,
  calculateAge,
  ageBucket,
} from '../shared/utils/ageUtils';

// ─── MIN_AGE ────────────────────────────────────────────────────────────────

describe('MIN_AGE', () => {
  it('is 13', () => {
    expect(MIN_AGE).toBe(13);
  });
});

// ─── parseDob ───────────────────────────────────────────────────────────────

describe('parseDob', () => {
  it('parses a valid YYYY-MM-DD as UTC midnight', () => {
    const d = parseDob('1990-05-15');
    expect(d).not.toBeNull();
    expect(d!.getUTCFullYear()).toBe(1990);
    expect(d!.getUTCMonth()).toBe(4); // zero-indexed
    expect(d!.getUTCDate()).toBe(15);
    expect(d!.getUTCHours()).toBe(0);
  });

  it('rejects malformed strings', () => {
    expect(parseDob('')).toBeNull();
    expect(parseDob('1990/05/15')).toBeNull();
    expect(parseDob('05-15-1990')).toBeNull();
    expect(parseDob('1990-5-15')).toBeNull();
    expect(parseDob('not a date')).toBeNull();
  });

  it('rejects future dates', () => {
    const next = new Date();
    next.setUTCFullYear(next.getUTCFullYear() + 1);
    const raw = next.toISOString().substring(0, 10);
    expect(parseDob(raw)).toBeNull();
  });

  it('rejects years before 1900', () => {
    expect(parseDob('1899-12-31')).toBeNull();
    expect(parseDob('1800-01-01')).toBeNull();
  });

  it('accepts 1900-01-01 exactly', () => {
    expect(parseDob('1900-01-01')).not.toBeNull();
  });
});

// ─── calculateAge ───────────────────────────────────────────────────────────

describe('calculateAge', () => {
  const atDate = (y: number, m: number, d: number) =>
    new Date(Date.UTC(y, m - 1, d));

  it('returns 0 on the day of birth', () => {
    const dob = atDate(2020, 5, 15);
    const now = atDate(2020, 5, 15);
    expect(calculateAge(dob, now)).toBe(0);
  });

  it('returns the exact completed-year age on the birthday', () => {
    const dob = atDate(2010, 5, 15);
    const now = atDate(2023, 5, 15);
    expect(calculateAge(dob, now)).toBe(13);
  });

  it('returns one less than the calendar-year difference the day before the birthday', () => {
    const dob = atDate(2010, 5, 15);
    const now = atDate(2023, 5, 14);
    expect(calculateAge(dob, now)).toBe(12);
  });

  it('returns the full age the day after the birthday', () => {
    const dob = atDate(2010, 5, 15);
    const now = atDate(2023, 5, 16);
    expect(calculateAge(dob, now)).toBe(13);
  });

  it('handles leap-year birthdays on non-leap years — still 12 on Feb 28', () => {
    // Born 2012-02-29. 2025 is not a leap year.
    const dob = atDate(2012, 2, 29);
    const feb28 = atDate(2025, 2, 28);
    expect(calculateAge(dob, feb28)).toBe(12);
  });

  it('handles leap-year birthdays on non-leap years — turns 13 on March 1', () => {
    const dob = atDate(2012, 2, 29);
    const march1 = atDate(2025, 3, 1);
    expect(calculateAge(dob, march1)).toBe(13);
  });

  it('handles cross-century births', () => {
    const dob = atDate(1925, 1, 1);
    const now = atDate(2025, 1, 1);
    expect(calculateAge(dob, now)).toBe(100);
  });

  it('handles month rollover correctly', () => {
    // Born December; "today" is next year's January — full year not yet elapsed.
    const dob = atDate(2010, 12, 15);
    const now = atDate(2023, 1, 15);
    expect(calculateAge(dob, now)).toBe(12);
  });
});

// ─── ageBucket ──────────────────────────────────────────────────────────────

describe('ageBucket', () => {
  it('returns "under_13" below the minimum', () => {
    expect(ageBucket(0)).toBe('under_13');
    expect(ageBucket(12)).toBe('under_13');
  });

  it('returns "13-17" at the minimum and through 17', () => {
    expect(ageBucket(13)).toBe('13-17');
    expect(ageBucket(17)).toBe('13-17');
  });

  it('returns "18-24"', () => {
    expect(ageBucket(18)).toBe('18-24');
    expect(ageBucket(24)).toBe('18-24');
  });

  it('returns "25-34"', () => {
    expect(ageBucket(25)).toBe('25-34');
    expect(ageBucket(34)).toBe('25-34');
  });

  it('returns "35-44"', () => {
    expect(ageBucket(35)).toBe('35-44');
    expect(ageBucket(44)).toBe('35-44');
  });

  it('returns "45+" for 45 and up', () => {
    expect(ageBucket(45)).toBe('45+');
    expect(ageBucket(100)).toBe('45+');
  });
});
