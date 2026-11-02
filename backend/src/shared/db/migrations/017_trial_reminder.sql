-- Trial-ending reminder (notifyTrialEnding timer → trialReminderService.ts).
--
-- trial_reminder_sent_for: the users.trial_ends_at value a "your free trial
-- ends soon" push was last delivered for. The hourly timer only reminds users
-- whose value IS DISTINCT FROM their current trial_ends_at, so each trial end
-- gets at most one reminder, and an SQL trial extension (the sanctioned
-- emergency unblock — migration 013) re-arms it for the new end date.
--
-- Additive + nullable: safe for a rolling deploy. Apply BEFORE publishing the
-- backend that registers notifyTrialEnding — until then its hourly query
-- fails (logged; no user impact, nothing else reads the column).

ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_reminder_sent_for TIMESTAMPTZ;
