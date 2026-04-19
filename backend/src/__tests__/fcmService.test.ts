import { buildFcmMessageBody } from '../shared/services/fcmService';

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
