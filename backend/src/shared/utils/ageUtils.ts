/**
 * Age-gate utilities for the 13+ sign-up check.
 *
 * Privacy posture: DOB flows through these functions in memory during a
 * single auth verify request. It is never persisted, logged, or passed
 * to telemetry. Only the coarse `ageBucket` ever leaves this module.
 *
 * Policy constant: MIN_AGE = 13. Mirrored in `app/lib/core/utils/age_utils.dart`
 * and declared in `website/privacy.html` §11. If the policy ever changes,
 * all three must move together.
 */

export const MIN_AGE = 13;

/**
 * Parse an ISO-ish date-of-birth string (YYYY-MM-DD only). Returns the
 * corresponding UTC-midnight Date, or null if the input is malformed,
 * in the future, or before 1900.
 */
export function parseDob(raw: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const d = new Date(raw + 'T00:00:00Z');
  if (isNaN(d.getTime())) return null;
  if (d > new Date()) return null;
  if (d.getUTCFullYear() < 1900) return null;
  return d;
}

/**
 * Compute age in completed years using UTC year/month/day. Both inputs
 * should be Date objects (any time-of-day is ignored).
 *
 * Timezone note: both sides of the age gate (backend + Flutter client)
 * compute in UTC. Worst case, a user in UTC+ timezones on their birthday
 * sees themselves turn 13 "tomorrow" in app time. Acceptable drift.
 */
export function calculateAge(dob: Date, now: Date = new Date()): number {
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const m = now.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) age--;
  return age;
}

/**
 * Coarse age bucket for telemetry. Never log raw age or DOB; log the
 * bucket. Matches the demographic groupings in the PRD target audience.
 */
export function ageBucket(age: number): string {
  if (age < 13) return 'under_13';
  if (age < 18) return '13-17';
  if (age < 25) return '18-24';
  if (age < 35) return '25-34';
  if (age < 45) return '35-44';
  return '45+';
}
