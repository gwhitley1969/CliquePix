/**
 * Reactor-list tests for GET /api/photos/:id/reactions and the video
 * equivalent. Exercises listReactionsForMedia directly with mocked deps —
 * pattern matches avatarEnricher.test.ts (jest.mock + direct invocation).
 *
 * The 7 cases enumerated in `plans/i-want-you-to-serene-swan.md`:
 *   1. happy path photo
 *   2. happy path video
 *   3. non-clique-member 404
 *   4. empty reactor list
 *   5. same user with multiple reaction types → 2 rows in reactors[]
 *   6. avatar enrichment runs once per row
 *   7. reactor with null avatar_blob_path → null URLs (initials fallback)
 */

import type { HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

// ─── Mocks ───────────────────────────────────────────────────────────────

jest.mock('../shared/middleware/authMiddleware', () => ({
  authenticateRequest: jest.fn(),
}));

jest.mock('../shared/services/dbService', () => ({
  query: jest.fn(),
  queryOne: jest.fn(),
  execute: jest.fn(),
}));

jest.mock('../shared/services/sasService', () => ({
  generateViewSas: jest.fn((path: string) =>
    Promise.resolve(`https://stub.blob.core.windows.net/photos/${path}?sig=stub`),
  ),
}));

jest.mock('../shared/services/telemetryService', () => ({
  trackEvent: jest.fn(),
}));

const enrichUserAvatarMock = jest.fn();
jest.mock('../shared/services/avatarEnricher', () => ({
  enrichUserAvatar: (...args: unknown[]) => enrichUserAvatarMock(...args),
}));

import { listReactionsForMedia } from '../functions/reactions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { query, queryOne } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';

// ─── Helpers ─────────────────────────────────────────────────────────────

const TEST_USER_ID = '11111111-1111-1111-1111-111111111111';
const PHOTO_ID = '22222222-2222-2222-2222-222222222222';
const VIDEO_ID = '33333333-3333-3333-3333-333333333333';

function fakeReq(): HttpRequest {
  return {} as unknown as HttpRequest;
}
function fakeCtx(): InvocationContext {
  return { invocationId: 'inv-test' } as unknown as InvocationContext;
}

function bodyOf(res: HttpResponseInit): { data?: unknown; error?: unknown } {
  // successResponse / errorResponse populate res.jsonBody (not res.body).
  return res.jsonBody as { data?: unknown; error?: unknown };
}

beforeEach(() => {
  jest.clearAllMocks();
  (authenticateRequest as jest.Mock).mockResolvedValue({ id: TEST_USER_ID });
  // Default: caller is a clique member of the event for the requested media.
  (queryOne as jest.Mock).mockResolvedValue({ id: PHOTO_ID });
  // Default avatar enrichment: pass-through. Each test can override.
  enrichUserAvatarMock.mockImplementation((ref: { avatar_blob_path: string | null; avatar_frame_preset: number | null }) =>
    Promise.resolve({
      avatar_url: ref.avatar_blob_path ? `https://stub/${ref.avatar_blob_path}?sig=stub` : null,
      avatar_thumb_url: ref.avatar_blob_path ? `https://stub/${ref.avatar_blob_path}.thumb?sig=stub` : null,
      avatar_updated_at: '2026-04-24T12:00:00.000Z',
      avatar_frame_preset: ref.avatar_frame_preset ?? 0,
    }),
  );
});

// ─── 1. Happy path: photo ────────────────────────────────────────────────

describe('GET /api/photos/{id}/reactions — happy path', () => {
  it('returns sorted reactors, by_type counts, and total_reactions', async () => {
    (query as jest.Mock).mockResolvedValueOnce([
      // newest first per the ORDER BY in the SQL
      {
        id: 'r1', user_id: 'u-paula', reaction_type: 'heart',
        created_at: new Date('2026-05-02T12:00:02Z'),
        display_name: 'Paula',
        avatar_blob_path: 'avatars/u-paula/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-paula/thumb.jpg',
        avatar_updated_at: new Date('2026-04-24T00:00:00Z'),
        avatar_frame_preset: 1,
      },
      {
        id: 'r2', user_id: 'u-bob', reaction_type: 'fire',
        created_at: new Date('2026-05-02T12:00:01Z'),
        display_name: 'Bob',
        avatar_blob_path: 'avatars/u-bob/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-bob/thumb.jpg',
        avatar_updated_at: new Date('2026-04-25T00:00:00Z'),
        avatar_frame_preset: 2,
      },
      {
        id: 'r3', user_id: 'u-carol', reaction_type: 'heart',
        created_at: new Date('2026-05-02T12:00:00Z'),
        display_name: 'Carol',
        avatar_blob_path: 'avatars/u-carol/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-carol/thumb.jpg',
        avatar_updated_at: new Date('2026-04-26T00:00:00Z'),
        avatar_frame_preset: 0,
      },
    ]);

    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    expect(res.status).toBe(200);
    const { data } = bodyOf(res) as { data: { media_id: string; total_reactions: number; by_type: Record<string, number>; reactors: Array<{ id: string; reaction_type: string; display_name: string; avatar_url: string | null }> } };
    expect(data.media_id).toBe(PHOTO_ID);
    expect(data.total_reactions).toBe(3);
    expect(data.by_type).toEqual({ heart: 2, laugh: 0, fire: 1, wow: 0 });
    expect(data.reactors.map((r) => r.id)).toEqual(['r1', 'r2', 'r3']);
    expect(data.reactors[0].display_name).toBe('Paula');
    expect(data.reactors[0].avatar_url).toContain('avatars/u-paula/original.jpg');
    expect(trackEvent).toHaveBeenCalledWith(
      'reactor_list_fetched',
      expect.objectContaining({ mediaId: PHOTO_ID, mediaType: 'photo', totalReactions: '3' }),
    );
  });
});

// ─── 2. Happy path: video ────────────────────────────────────────────────

describe('GET /api/videos/{id}/reactions — happy path', () => {
  it('returns the reactor list for a video and emits video telemetry', async () => {
    (queryOne as jest.Mock).mockResolvedValueOnce({ id: VIDEO_ID });
    (query as jest.Mock).mockResolvedValueOnce([
      {
        id: 'r1', user_id: 'u-paula', reaction_type: 'wow',
        created_at: new Date('2026-05-02T12:00:00Z'),
        display_name: 'Paula',
        avatar_blob_path: 'avatars/u-paula/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-paula/thumb.jpg',
        avatar_updated_at: new Date('2026-04-24T00:00:00Z'),
        avatar_frame_preset: 0,
      },
    ]);
    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), VIDEO_ID, 'video');
    expect(res.status).toBe(200);
    const { data } = bodyOf(res) as { data: { total_reactions: number; by_type: Record<string, number> } };
    expect(data.total_reactions).toBe(1);
    expect(data.by_type.wow).toBe(1);
    expect(trackEvent).toHaveBeenCalledWith(
      'reactor_list_fetched',
      expect.objectContaining({ mediaType: 'video', totalReactions: '1' }),
    );
  });
});

// ─── 3. Non-clique-member request ────────────────────────────────────────

describe('non-member', () => {
  it('returns 404 when membership query finds nothing', async () => {
    (queryOne as jest.Mock).mockResolvedValueOnce(null);
    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    expect(res.status).toBe(404);
    // Reactor query should never have been issued.
    expect(query).not.toHaveBeenCalled();
  });
});

// ─── 4. Empty reactor list ───────────────────────────────────────────────

describe('empty reactions', () => {
  it('returns total_reactions=0 and zeroed by_type', async () => {
    (query as jest.Mock).mockResolvedValueOnce([]);
    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    expect(res.status).toBe(200);
    const { data } = bodyOf(res) as { data: { total_reactions: number; by_type: Record<string, number>; reactors: unknown[] } };
    expect(data.total_reactions).toBe(0);
    expect(data.by_type).toEqual({ heart: 0, laugh: 0, fire: 0, wow: 0 });
    expect(data.reactors).toEqual([]);
  });
});

// ─── 5. Same user, multiple reaction types ──────────────────────────────

describe('same user with multiple reactions', () => {
  it('returns one row per reaction (not deduped server-side)', async () => {
    (query as jest.Mock).mockResolvedValueOnce([
      {
        id: 'r1', user_id: 'u-paula', reaction_type: 'heart',
        created_at: new Date('2026-05-02T12:00:01Z'),
        display_name: 'Paula',
        avatar_blob_path: 'avatars/u-paula/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-paula/thumb.jpg',
        avatar_updated_at: new Date(),
        avatar_frame_preset: 0,
      },
      {
        id: 'r2', user_id: 'u-paula', reaction_type: 'fire',
        created_at: new Date('2026-05-02T12:00:00Z'),
        display_name: 'Paula',
        avatar_blob_path: 'avatars/u-paula/original.jpg',
        avatar_thumb_blob_path: 'avatars/u-paula/thumb.jpg',
        avatar_updated_at: new Date(),
        avatar_frame_preset: 0,
      },
    ]);
    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    const { data } = bodyOf(res) as { data: { total_reactions: number; by_type: Record<string, number>; reactors: Array<{ user_id: string; reaction_type: string }> } };
    expect(data.total_reactions).toBe(2);
    expect(data.by_type).toEqual({ heart: 1, laugh: 0, fire: 1, wow: 0 });
    expect(data.reactors).toHaveLength(2);
    expect(data.reactors.every((r) => r.user_id === 'u-paula')).toBe(true);
  });
});

// ─── 6. Avatar enrichment runs per row ──────────────────────────────────

describe('avatar enrichment', () => {
  it('calls enrichUserAvatar once per reactor row', async () => {
    (query as jest.Mock).mockResolvedValueOnce([
      { id: 'r1', user_id: 'u-a', reaction_type: 'heart', created_at: new Date(), display_name: 'A', avatar_blob_path: 'a/o.jpg', avatar_thumb_blob_path: 'a/t.jpg', avatar_updated_at: new Date(), avatar_frame_preset: 1 },
      { id: 'r2', user_id: 'u-b', reaction_type: 'heart', created_at: new Date(), display_name: 'B', avatar_blob_path: 'b/o.jpg', avatar_thumb_blob_path: 'b/t.jpg', avatar_updated_at: new Date(), avatar_frame_preset: 2 },
      { id: 'r3', user_id: 'u-c', reaction_type: 'heart', created_at: new Date(), display_name: 'C', avatar_blob_path: 'c/o.jpg', avatar_thumb_blob_path: 'c/t.jpg', avatar_updated_at: new Date(), avatar_frame_preset: 3 },
    ]);
    await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    expect(enrichUserAvatarMock).toHaveBeenCalledTimes(3);
  });
});

// ─── 7. Reactor without an avatar (initials-fallback) ───────────────────

describe('reactor without avatar', () => {
  it('returns null avatar_url when avatar_blob_path is null', async () => {
    (query as jest.Mock).mockResolvedValueOnce([
      {
        id: 'r1', user_id: 'u-noavatar', reaction_type: 'heart',
        created_at: new Date(),
        display_name: 'Newcomer',
        avatar_blob_path: null,
        avatar_thumb_blob_path: null,
        avatar_updated_at: null,
        avatar_frame_preset: null,
      },
    ]);
    const res = await listReactionsForMedia(fakeReq(), fakeCtx(), PHOTO_ID, 'photo');
    const { data } = bodyOf(res) as { data: { reactors: Array<{ avatar_url: string | null; avatar_thumb_url: string | null; avatar_frame_preset: number }> } };
    expect(data.reactors[0].avatar_url).toBeNull();
    expect(data.reactors[0].avatar_thumb_url).toBeNull();
    expect(data.reactors[0].avatar_frame_preset).toBe(0);
  });
});
