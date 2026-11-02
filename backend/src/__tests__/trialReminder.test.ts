// Trial-ending reminder: one push, about a day before the 7-day app trial
// ends, to users who haven't subscribed. Before this, a trial user who didn't
// happen to reopen the app after day 7 never saw the paywall at all.

const queryMock = jest.fn();
const execMock = jest.fn();
const sendMock = jest.fn();
const trackMock = jest.fn();

jest.mock('../shared/services/dbService', () => ({
  query: (...args: unknown[]) => queryMock(...args),
  execute: (...args: unknown[]) => execMock(...args),
  queryOne: jest.fn(),
}));

jest.mock('../shared/services/fcmService', () => ({
  sendToMultipleTokens: (...args: unknown[]) => sendMock(...args),
}));

jest.mock('../shared/services/telemetryService', () => ({
  trackEvent: (...args: unknown[]) => trackMock(...args),
}));

import {
  sendTrialEndingReminders,
  TRIAL_REMINDER_BODY,
  TRIAL_REMINDER_TITLE,
} from '../shared/services/trialReminderService';

const delivered = { permanentlyInvalid: [], totalFailed: 0 };

function row(userId: string, token: string) {
  return { user_id: userId, token };
}

beforeEach(() => {
  queryMock.mockReset().mockResolvedValue([]);
  execMock.mockReset().mockResolvedValue(1);
  sendMock.mockReset().mockResolvedValue(delivered);
  trackMock.mockReset();
});

describe('sendTrialEndingReminders', () => {
  it('sends nothing and records nothing when no trial is ending', async () => {
    const result = await sendTrialEndingReminders();

    expect(sendMock).not.toHaveBeenCalled();
    expect(execMock).not.toHaveBeenCalled();
    expect(result).toEqual({ candidates: 0, users: 0, reminded: 0, failed: 0 });
  });

  it('targets only unsubscribed users whose trial ends 23-25h out, once per trial end', async () => {
    await sendTrialEndingReminders();

    const sql = queryMock.mock.calls[0][0] as string;
    expect(sql).toMatch(/NOT u\.entitlement_active/);
    expect(sql).toMatch(/u\.trial_ends_at > NOW\(\) \+ INTERVAL '23 hours'/);
    expect(sql).toMatch(/u\.trial_ends_at <= NOW\(\) \+ INTERVAL '25 hours'/);
    expect(sql).toMatch(/u\.trial_reminder_sent_for IS DISTINCT FROM u\.trial_ends_at/);
  });

  it("sends one push per user, to all of that user's devices", async () => {
    queryMock.mockResolvedValue([row('u1', 't1'), row('u1', 't2'), row('u2', 't3')]);

    await sendTrialEndingReminders();

    expect(sendMock).toHaveBeenCalledTimes(2);
    expect(sendMock).toHaveBeenCalledWith(['t1', 't2'], TRIAL_REMINDER_TITLE, TRIAL_REMINDER_BODY, {
      type: 'trial_ending',
    });
    expect(sendMock).toHaveBeenCalledWith(['t3'], TRIAL_REMINDER_TITLE, TRIAL_REMINDER_BODY, {
      type: 'trial_ending',
    });
  });

  it('records the reminder only for users with at least one delivered push', async () => {
    queryMock.mockResolvedValue([row('u1', 't1'), row('u1', 't2'), row('u2', 't3')]);
    sendMock.mockImplementation(async (tokens: string[]) =>
      tokens.includes('t1')
        ? { permanentlyInvalid: [], totalFailed: 2 } // every u1 device failed
        : delivered,
    );

    const result = await sendTrialEndingReminders();

    const update = execMock.mock.calls.find(([sql]) => /trial_reminder_sent_for/.test(sql));
    expect(update).toBeDefined();
    expect(update![0]).toMatch(/SET trial_reminder_sent_for = trial_ends_at/);
    expect(update![1]).toEqual([['u2']]);
    expect(result).toEqual({ candidates: 3, users: 2, reminded: 1, failed: 2 });
  });

  it('purges tokens FCM reports as permanently invalid', async () => {
    queryMock.mockResolvedValue([row('u1', 'dead'), row('u1', 'live')]);
    sendMock.mockResolvedValue({ permanentlyInvalid: ['dead'], totalFailed: 1 });

    await sendTrialEndingReminders();

    expect(execMock).toHaveBeenCalledWith('DELETE FROM push_tokens WHERE token = ANY($1)', [['dead']]);
  });

  it("keeps going when one user's send throws", async () => {
    queryMock.mockResolvedValue([row('u1', 't1'), row('u2', 't2')]);
    sendMock.mockRejectedValueOnce(new Error('fcm down')).mockResolvedValueOnce(delivered);

    const result = await sendTrialEndingReminders();

    const update = execMock.mock.calls.find(([sql]) => /trial_reminder_sent_for/.test(sql));
    expect(update![1]).toEqual([['u2']]);
    expect(result.reminded).toBe(1);
    expect(result.failed).toBe(1);
  });

  it('reports the send to telemetry as notification_sent', async () => {
    queryMock.mockResolvedValue([row('u1', 't1')]);

    await sendTrialEndingReminders();

    expect(trackMock).toHaveBeenCalledWith('notification_sent', {
      type: 'trial_ending',
      count: '1',
      failed: '0',
    });
  });
});
