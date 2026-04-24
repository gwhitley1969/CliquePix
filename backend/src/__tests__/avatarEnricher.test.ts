import { enrichUserAvatar, shouldPromptForAvatar, buildAuthUserResponse } from '../shared/services/avatarEnricher';

// Mock sasService so we don't hit Azure during unit tests. The enricher
// should call generateViewSas(path, 3600) for each non-null blob path.
jest.mock('../shared/services/sasService', () => ({
  generateViewSas: jest.fn((path: string, _seconds: number) =>
    Promise.resolve(`https://stub.blob.core.windows.net/photos/${path}?sig=stub`),
  ),
}));

// ─── enrichUserAvatar ──────────────────────────────────────────────────────────

describe('enrichUserAvatar', () => {
  it('returns null URLs when avatar_blob_path is null', async () => {
    const out = await enrichUserAvatar({
      avatar_blob_path: null,
      avatar_thumb_blob_path: null,
      avatar_updated_at: null,
      avatar_frame_preset: 0,
    });
    expect(out.avatar_url).toBeNull();
    expect(out.avatar_thumb_url).toBeNull();
    expect(out.avatar_updated_at).toBeNull();
    expect(out.avatar_frame_preset).toBe(0);
  });

  it('returns signed URLs when blob paths are populated', async () => {
    const updated = new Date('2026-04-24T12:00:00.000Z');
    const out = await enrichUserAvatar({
      avatar_blob_path: 'avatars/user-123/original.jpg',
      avatar_thumb_blob_path: 'avatars/user-123/thumb.jpg',
      avatar_updated_at: updated,
      avatar_frame_preset: 3,
    });
    expect(out.avatar_url).toContain('avatars/user-123/original.jpg');
    expect(out.avatar_url).toContain('sig=');
    expect(out.avatar_thumb_url).toContain('avatars/user-123/thumb.jpg');
    expect(out.avatar_updated_at).toBe('2026-04-24T12:00:00.000Z');
    expect(out.avatar_frame_preset).toBe(3);
  });

  it('normalizes frame_preset null to 0', async () => {
    const out = await enrichUserAvatar({
      avatar_blob_path: null,
      avatar_thumb_blob_path: null,
      avatar_updated_at: null,
      avatar_frame_preset: null as unknown as number,
    });
    expect(out.avatar_frame_preset).toBe(0);
  });

  it('accepts avatar_updated_at as a string', async () => {
    const out = await enrichUserAvatar({
      avatar_blob_path: 'avatars/u/original.jpg',
      avatar_thumb_blob_path: 'avatars/u/thumb.jpg',
      avatar_updated_at: '2026-04-24T12:00:00.000Z',
      avatar_frame_preset: 0,
    });
    expect(out.avatar_updated_at).toBe('2026-04-24T12:00:00.000Z');
  });

  it('handles only thumb missing (thumb gen failed)', async () => {
    const out = await enrichUserAvatar({
      avatar_blob_path: 'avatars/u/original.jpg',
      avatar_thumb_blob_path: null,
      avatar_updated_at: new Date(),
      avatar_frame_preset: 0,
    });
    expect(out.avatar_url).not.toBeNull();
    expect(out.avatar_thumb_url).toBeNull();
  });
});

// ─── shouldPromptForAvatar ─────────────────────────────────────────────────────

describe('shouldPromptForAvatar', () => {
  const freshUser = {
    avatar_blob_path: null,
    avatar_prompt_dismissed: false,
    avatar_prompt_snoozed_until: null,
  };

  it('prompts a brand-new user with no avatar and no prior choice', () => {
    expect(shouldPromptForAvatar(freshUser)).toBe(true);
  });

  it('suppresses prompt when user has uploaded an avatar', () => {
    expect(
      shouldPromptForAvatar({
        ...freshUser,
        avatar_blob_path: 'avatars/user-123/original.jpg',
      }),
    ).toBe(false);
  });

  it('suppresses prompt when dismissed ("No Thanks")', () => {
    expect(
      shouldPromptForAvatar({
        ...freshUser,
        avatar_prompt_dismissed: true,
      }),
    ).toBe(false);
  });

  it('suppresses prompt during active snooze window ("Maybe Later")', () => {
    const now = new Date('2026-04-24T12:00:00Z');
    const future = new Date('2026-05-01T12:00:00Z'); // 7 days out
    expect(
      shouldPromptForAvatar(
        {
          ...freshUser,
          avatar_prompt_snoozed_until: future,
        },
        now,
      ),
    ).toBe(false);
  });

  it('re-enables prompt after snooze expires', () => {
    const now = new Date('2026-05-02T12:00:00Z');
    const past = new Date('2026-05-01T12:00:00Z'); // snooze ended yesterday
    expect(
      shouldPromptForAvatar(
        {
          ...freshUser,
          avatar_prompt_snoozed_until: past,
        },
        now,
      ),
    ).toBe(true);
  });

  it('accepts snooze timestamp as a string', () => {
    const now = new Date('2026-04-24T12:00:00Z');
    expect(
      shouldPromptForAvatar(
        {
          ...freshUser,
          avatar_prompt_snoozed_until: '2026-05-01T12:00:00Z',
        },
        now,
      ),
    ).toBe(false);
  });

  it('avatar presence overrides snooze (user uploaded BEFORE snooze expired)', () => {
    const now = new Date('2026-04-24T12:00:00Z');
    expect(
      shouldPromptForAvatar(
        {
          avatar_blob_path: 'avatars/u/original.jpg',
          avatar_prompt_dismissed: false,
          avatar_prompt_snoozed_until: new Date('2026-05-01T12:00:00Z'),
        },
        now,
      ),
    ).toBe(false);
  });
});

// ─── buildAuthUserResponse ─────────────────────────────────────────────────────

describe('buildAuthUserResponse', () => {
  const baseRow = {
    id: 'user-id-1',
    display_name: 'Gene Whitley',
    email_or_phone: 'gene@example.com',
    avatar_blob_path: null,
    avatar_thumb_blob_path: null,
    avatar_updated_at: null,
    avatar_frame_preset: 0,
    avatar_prompt_dismissed: false,
    avatar_prompt_snoozed_until: null,
    created_at: new Date('2026-04-01T00:00:00Z'),
  };

  it('returns canonical auth shape for a fresh user', async () => {
    const out = await buildAuthUserResponse(baseRow);
    expect(out).toMatchObject({
      id: 'user-id-1',
      display_name: 'Gene Whitley',
      email_or_phone: 'gene@example.com',
      avatar_url: null,
      avatar_thumb_url: null,
      avatar_updated_at: null,
      avatar_frame_preset: 0,
      should_prompt_for_avatar: true,
    });
  });

  it('emits should_prompt_for_avatar=false once user has an avatar', async () => {
    const out = await buildAuthUserResponse({
      ...baseRow,
      avatar_blob_path: 'avatars/user-id-1/original.jpg',
      avatar_thumb_blob_path: 'avatars/user-id-1/thumb.jpg',
      avatar_updated_at: new Date('2026-04-24T12:00:00Z'),
    });
    expect(out.should_prompt_for_avatar).toBe(false);
    expect(out.avatar_url).toContain('avatars/user-id-1/original.jpg');
    expect(out.avatar_thumb_url).toContain('avatars/user-id-1/thumb.jpg');
  });

  it('honors dismiss flag', async () => {
    const out = await buildAuthUserResponse({
      ...baseRow,
      avatar_prompt_dismissed: true,
    });
    expect(out.should_prompt_for_avatar).toBe(false);
  });
});
