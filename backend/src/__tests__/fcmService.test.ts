import { buildFcmMessageBody, isPermanentTokenError } from '../shared/services/fcmService';

const FCM_ERR_TYPE = 'type.googleapis.com/google.firebase.fcm.v1.FcmError';

describe('isPermanentTokenError — only purge genuinely-dead tokens', () => {
  describe('PERMANENT (true) — token is dead, safe to delete', () => {
    it('404 with FcmError UNREGISTERED details', () => {
      const body = JSON.stringify({
        error: { status: 'NOT_FOUND', details: [{ '@type': FCM_ERR_TYPE, errorCode: 'UNREGISTERED' }] },
      });
      expect(isPermanentTokenError(404, body)).toBe(true);
    });
    it('404 with only error.status=NOT_FOUND (no details)', () => {
      expect(isPermanentTokenError(404, JSON.stringify({ error: { status: 'NOT_FOUND' } }))).toBe(true);
    });
    it('400 with error.status=INVALID_ARGUMENT', () => {
      expect(isPermanentTokenError(400, JSON.stringify({ error: { status: 'INVALID_ARGUMENT' } }))).toBe(true);
    });
    it('400 with FcmError INVALID_ARGUMENT details', () => {
      const body = JSON.stringify({
        error: { details: [{ '@type': FCM_ERR_TYPE, errorCode: 'INVALID_ARGUMENT' }] },
      });
      expect(isPermanentTokenError(400, body)).toBe(true);
    });
  });

  describe('TRANSIENT (false) — must NOT purge', () => {
    it.each([401, 403, 429, 500, 502, 503])('status %i is transient', (status) => {
      expect(isPermanentTokenError(status, JSON.stringify({ error: { status: 'UNAVAILABLE' } }))).toBe(false);
    });
    it('502 with non-JSON HTML body does not throw and is transient', () => {
      expect(isPermanentTokenError(502, '<html>502 Bad Gateway</html>')).toBe(false);
    });
    it('404 with empty body is transient (no FCM signal)', () => {
      expect(isPermanentTokenError(404, '')).toBe(false);
    });
    it('400 with malformed JSON is transient', () => {
      expect(isPermanentTokenError(400, '{not valid json')).toBe(false);
    });
    it('404 whose error.status is INTERNAL (not NOT_FOUND/UNREGISTERED) is transient', () => {
      expect(isPermanentTokenError(404, JSON.stringify({ error: { status: 'INTERNAL' } }))).toBe(false);
    });
  });
});

describe('buildFcmMessageBody', () => {
  describe('visible push (silent=false or omitted)', () => {
    it('includes a notification block with title and body', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        title: 'Hello',
        body: 'World',
        data: { k: 'v' },
      });
      expect(body).toEqual({
        message: {
          token: 'abc',
          notification: { title: 'Hello', body: 'World' },
          data: { k: 'v' },
        },
      });
    });

    it('does NOT set apns or android blocks for visible push', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        title: 'Hello',
        body: 'World',
      }) as { message: Record<string, unknown> };
      expect(body.message.apns).toBeUndefined();
      expect(body.message.android).toBeUndefined();
    });
  });

  describe('silent push (silent=true)', () => {
    it('omits the notification block entirely', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        data: { type: 'token_refresh' },
        silent: true,
      }) as { message: Record<string, unknown> };
      expect(body.message.notification).toBeUndefined();
    });

    it('sets apns headers for iOS background wake (priority 5, push-type background, content-available 1)', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        data: { type: 'token_refresh' },
        silent: true,
      }) as {
        message: {
          apns: {
            headers: Record<string, string>;
            payload: { aps: Record<string, unknown> };
          };
        };
      };
      expect(body.message.apns.headers['apns-push-type']).toBe('background');
      expect(body.message.apns.headers['apns-priority']).toBe('5');
      expect(body.message.apns.headers['apns-topic']).toBeDefined();
      expect(body.message.apns.payload.aps['content-available']).toBe(1);
    });

    it('sets android priority high so data-only message wakes the app', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        data: { type: 'token_refresh' },
        silent: true,
      }) as { message: { android: { priority: string } } };
      expect(body.message.android.priority).toBe('high');
    });

    it('includes the data payload', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        data: { type: 'token_refresh', userId: 'u1' },
        silent: true,
      }) as { message: { data: Record<string, string> } };
      expect(body.message.data).toEqual({ type: 'token_refresh', userId: 'u1' });
    });

    it('ignores title and body when silent', () => {
      const body = buildFcmMessageBody({
        token: 'abc',
        title: 'ignored',
        body: 'ignored',
        data: { type: 'token_refresh' },
        silent: true,
      }) as { message: Record<string, unknown> };
      expect(body.message.notification).toBeUndefined();
      expect(body.message.title).toBeUndefined();
      expect(body.message.body).toBeUndefined();
    });
  });
});
