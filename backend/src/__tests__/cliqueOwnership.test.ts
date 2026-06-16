/**
 * Clique ownership lifecycle (added 2026-06-16).
 *
 * Covers the shared successor-selection + lockstep-promotion helpers that
 * deleteMe / leaveClique use, and the new POST /transfer-ownership endpoint.
 * Context: a deleted creator left cliques ownerless (FK SET NULL + the owner's
 * clique_members row CASCADE-deleted). See docs/DEPLOYMENT_STATUS.md.
 */

import type { HttpRequest, InvocationContext } from '@azure/functions';

// ─── Mocks (set before importing the modules under test) ───────────────────
jest.mock('../shared/services/dbService', () => ({
  query: jest.fn(),
  queryOne: jest.fn(),
  execute: jest.fn(),
}));
jest.mock('../shared/middleware/authMiddleware', () => ({ authenticateRequest: jest.fn() }));
jest.mock('../shared/middleware/requireActiveEntitlement', () => ({ requireActiveEntitlement: jest.fn() }));
jest.mock('../shared/services/telemetryService', () => ({ trackEvent: jest.fn() }));
// cliques.ts pulls these in transitively at module load — keep them inert.
jest.mock('../shared/services/blobService', () => ({ deleteMediaAssets: jest.fn() }));
jest.mock('../shared/services/fcmService', () => ({ sendToMultipleTokens: jest.fn() }));
jest.mock('../shared/services/avatarEnricher', () => ({ enrichUserAvatar: jest.fn() }));

import { selectSuccessorUserId, promoteToOwner, notifyNewOwner } from '../shared/services/cliqueOwnershipService';
import { transferOwnership } from '../functions/cliques';
import { query, queryOne, execute } from '../shared/services/dbService';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { trackEvent } from '../shared/services/telemetryService';
import { sendToMultipleTokens } from '../shared/services/fcmService';

const CLIQUE = '33333333-3333-3333-3333-333333333333';
const OWNER = '11111111-1111-1111-1111-111111111111';
const TARGET = '22222222-2222-2222-2222-222222222222';
const OUTSIDER = '44444444-4444-4444-4444-444444444444';

const qOne = queryOne as jest.Mock;
const exec = execute as jest.Mock;
const auth = authenticateRequest as jest.Mock;

beforeEach(() => {
  (query as jest.Mock).mockReset().mockResolvedValue([]);
  qOne.mockReset();
  exec.mockReset().mockResolvedValue(1);
  auth.mockReset();
  (trackEvent as jest.Mock).mockReset();
  (sendToMultipleTokens as jest.Mock).mockReset();
});

function ctx(): InvocationContext {
  return { invocationId: 'inv-test', error: jest.fn() } as unknown as InvocationContext;
}
function req(body: unknown): HttpRequest {
  return {
    params: { cliqueId: CLIQUE },
    json: async () => body,
  } as unknown as HttpRequest;
}

describe('selectSuccessorUserId', () => {
  it('returns the longest-tenured OTHER member (deterministic ordering)', async () => {
    qOne.mockResolvedValueOnce({ user_id: TARGET });
    const result = await selectSuccessorUserId(CLIQUE, OWNER);
    expect(result).toBe(TARGET);
    const [sql, params] = qOne.mock.calls[0];
    expect(sql).toContain('user_id <> $2');
    expect(sql).toContain('ORDER BY joined_at ASC, user_id ASC');
    expect(sql).toContain('LIMIT 1');
    expect(params).toEqual([CLIQUE, OWNER]);
  });

  it('returns null when there is no other member', async () => {
    qOne.mockResolvedValueOnce(null);
    expect(await selectSuccessorUserId(CLIQUE, OWNER)).toBeNull();
  });
});

describe('promoteToOwner', () => {
  it('sets role=owner AND created_by in lockstep, both pointing at the successor', async () => {
    await promoteToOwner(CLIQUE, TARGET);
    expect(exec).toHaveBeenCalledTimes(2);
    const [roleSql, roleParams] = exec.mock.calls[0];
    expect(roleSql).toContain('UPDATE clique_members SET role');
    expect(roleSql).toContain("'owner'");
    expect(roleParams).toEqual([CLIQUE, TARGET]);
    const [cbSql, cbParams] = exec.mock.calls[1];
    expect(cbSql).toContain('UPDATE cliques SET created_by_user_id');
    expect(cbParams).toEqual([CLIQUE, TARGET]);
  });
});

describe('notifyNewOwner', () => {
  it('writes an in-app row and pushes FCM to the new owner', async () => {
    qOne.mockResolvedValueOnce({ name: 'Trip Crew' }); // clique-name lookup
    (query as jest.Mock).mockResolvedValueOnce([{ token: 'tok-1' }]); // push tokens
    (sendToMultipleTokens as jest.Mock).mockResolvedValueOnce({ permanentlyInvalid: [], totalFailed: 0 });

    await notifyNewOwner(CLIQUE, TARGET);

    const insert = exec.mock.calls.find((c) => String(c[0]).includes('INSERT INTO notifications'));
    expect(insert).toBeDefined();
    expect(insert![0]).toContain("'clique_ownership_transferred'");
    expect(insert![1][0]).toBe(TARGET);
    expect(insert![1][1]).toContain(CLIQUE);
    expect(sendToMultipleTokens).toHaveBeenCalledWith(
      ['tok-1'],
      expect.any(String),
      expect.stringContaining('Trip Crew'),
      { clique_id: CLIQUE },
    );
  });

  it('is best-effort: a DB failure never throws (ownership change is already committed)', async () => {
    qOne.mockRejectedValueOnce(new Error('db down'));
    await expect(notifyNewOwner(CLIQUE, TARGET)).resolves.toBeUndefined();
  });
});

describe('transferOwnership endpoint', () => {
  it('swaps roles atomically + updates created_by + emits telemetry on success', async () => {
    auth.mockResolvedValue({ id: OWNER });
    qOne
      .mockResolvedValueOnce({ user_id: OWNER, role: 'owner' }) // caller membership
      .mockResolvedValueOnce({ user_id: TARGET, role: 'member' }); // target membership

    const res = await transferOwnership(req({ user_id: TARGET }), ctx());

    expect(res.status ?? 200).toBe(200);
    // Single-statement CASE role swap, then lockstep created_by update.
    const swapSql = exec.mock.calls[0][0] as string;
    expect(swapSql).toContain('CASE WHEN user_id = $2');
    expect(swapSql).toContain("'owner'");
    expect(exec.mock.calls[0][1]).toEqual([CLIQUE, OWNER, TARGET]);
    expect(exec.mock.calls[1][0]).toContain('UPDATE cliques SET created_by_user_id');
    expect(exec.mock.calls[1][1]).toEqual([CLIQUE, TARGET]);
    expect(trackEvent).toHaveBeenCalledWith(
      'clique_ownership_transferred',
      expect.objectContaining({ cliqueId: CLIQUE, from: OWNER, to: TARGET, reason: 'explicit' }),
    );
  });

  it('rejects a non-owner caller with 403 and writes nothing', async () => {
    auth.mockResolvedValue({ id: OWNER });
    qOne.mockResolvedValueOnce({ user_id: OWNER, role: 'member' });
    const res = await transferOwnership(req({ user_id: TARGET }), ctx());
    expect(res.status).toBe(403);
    expect(exec).not.toHaveBeenCalled();
  });

  it('404s when the target is not a member', async () => {
    auth.mockResolvedValue({ id: OWNER });
    qOne
      .mockResolvedValueOnce({ user_id: OWNER, role: 'owner' })
      .mockResolvedValueOnce(null);
    const res = await transferOwnership(req({ user_id: OUTSIDER }), ctx());
    expect(res.status).toBe(404);
    expect(exec).not.toHaveBeenCalled();
  });

  it('400s when transferring to yourself', async () => {
    auth.mockResolvedValue({ id: OWNER });
    qOne.mockResolvedValueOnce({ user_id: OWNER, role: 'owner' });
    const res = await transferOwnership(req({ user_id: OWNER }), ctx());
    expect(res.status).toBe(400);
    expect(exec).not.toHaveBeenCalled();
  });

  it('400s on a non-UUID user_id before any DB work', async () => {
    auth.mockResolvedValue({ id: OWNER });
    const res = await transferOwnership(req({ user_id: 'not-a-uuid' }), ctx());
    expect(res.status).toBe(400);
    expect(qOne).not.toHaveBeenCalled();
  });
});
