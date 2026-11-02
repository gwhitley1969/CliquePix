import { query, execute } from './dbService';
import { sendToMultipleTokens } from './fcmService';
import { trackEvent } from './telemetryService';

// Trial-ending reminder (migration 017). One push about a day before the
// 7-day app trial (migration 013) ends, to users who haven't subscribed.
// Before this, a trial user who didn't reopen the app after day 7 never saw
// the paywall at all. Push-only, like dm_message: no notifications-table row
// (the type CHECK constraint doesn't allow one) — the client routes the tap
// to the subscribe flow and the Home banner covers the in-app side.
//
// Deduped per trial end via users.trial_reminder_sent_for: the reminder is
// recorded against the trial_ends_at it was sent for, so an SQL trial
// extension (the sanctioned emergency unblock) re-arms it for the new date.
// Recorded only after at least one device accepted the push, so a total FCM
// failure is retried on the next hourly run while still inside the window.

export const TRIAL_REMINDER_TITLE = 'Your free trial ends soon';
export const TRIAL_REMINDER_BODY = 'Subscribe to keep sharing photos and videos with your Cliques.';

export interface TrialReminderResult {
  /** Push-token rows matched (a user may have several devices). */
  candidates: number;
  users: number;
  /** Users with at least one delivered push. */
  reminded: number;
  /** Individual token sends that failed. */
  failed: number;
}

export async function sendTrialEndingReminders(
  onUserError?: (userId: string, err: unknown) => void,
): Promise<TrialReminderResult> {
  const candidates = await query<{ user_id: string; token: string }>(
    `SELECT pt.user_id, pt.token
       FROM push_tokens pt
       JOIN users u ON u.id = pt.user_id
      WHERE NOT u.entitlement_active
        AND u.trial_ends_at > NOW() + INTERVAL '23 hours'
        AND u.trial_ends_at <= NOW() + INTERVAL '25 hours'
        AND u.trial_reminder_sent_for IS DISTINCT FROM u.trial_ends_at`,
  );

  const byUser = new Map<string, string[]>();
  for (const c of candidates) {
    const tokens = byUser.get(c.user_id) ?? [];
    tokens.push(c.token);
    byUser.set(c.user_id, tokens);
  }

  let failed = 0;
  const reminded: string[] = [];

  for (const [userId, tokens] of byUser.entries()) {
    try {
      const sendResult = await sendToMultipleTokens(tokens, TRIAL_REMINDER_TITLE, TRIAL_REMINDER_BODY, {
        type: 'trial_ending',
      });
      failed += sendResult.totalFailed;

      // NOTIF-2: only purge PERMANENTLY-invalid tokens, never transient failures.
      if (sendResult.permanentlyInvalid.length > 0) {
        await execute('DELETE FROM push_tokens WHERE token = ANY($1)', [sendResult.permanentlyInvalid]);
      }

      if (tokens.length - sendResult.totalFailed > 0) {
        reminded.push(userId);
      }
    } catch (err) {
      failed += tokens.length;
      onUserError?.(userId, err);
    }
  }

  if (reminded.length > 0) {
    await execute('UPDATE users SET trial_reminder_sent_for = trial_ends_at WHERE id = ANY($1)', [reminded]);
  }

  trackEvent('notification_sent', {
    type: 'trial_ending',
    count: String(reminded.length),
    failed: String(failed),
  });

  return { candidates: candidates.length, users: byUser.size, reminded: reminded.length, failed };
}
