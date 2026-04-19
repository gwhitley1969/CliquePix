import { api } from '../client';
import type { Clique, CliqueMember } from '../../models';

export async function listCliques(): Promise<Clique[]> {
  const res = await api.get<{ data: Clique[] }>('/api/cliques');
  return res.data.data;
}

export async function getClique(cliqueId: string): Promise<Clique> {
  const res = await api.get<{ data: Clique }>(`/api/cliques/${cliqueId}`);
  return res.data.data;
}

export async function createClique(name: string): Promise<Clique> {
  const res = await api.post<{ data: Clique }>('/api/cliques', { name });
  return res.data.data;
}

// Backend returns { invite_code, invite_url } — the global camelize
// interceptor in api/client.ts converts those keys to camelCase, so the
// TS return type reflects the post-transform shape. If the interceptor
// ever changes, update both.
export async function getInvite(
  cliqueId: string,
): Promise<{ inviteCode: string; inviteUrl: string }> {
  const res = await api.post<{ data: { inviteCode: string; inviteUrl: string } }>(
    `/api/cliques/${cliqueId}/invite`,
  );
  return res.data.data;
}

export async function joinCliqueByCode(inviteCode: string): Promise<Clique> {
  // Backend route is `cliques/{cliqueId}/join` but the handler ignores the
  // path param and resolves the clique via `invite_code` in the body. The
  // mobile Flutter client passes `_` as a placeholder for the same reason
  // (app/lib/features/cliques/data/cliques_api.dart). Omitting the segment
  // returns 404 because the route pattern requires it.
  const res = await api.post<{ data: Clique }>(`/api/cliques/_/join`, {
    invite_code: inviteCode,
  });
  return res.data.data;
}

export async function listMembers(cliqueId: string): Promise<CliqueMember[]> {
  const res = await api.get<{ data: CliqueMember[] }>(`/api/cliques/${cliqueId}/members`);
  return res.data.data;
}

export async function leaveClique(cliqueId: string): Promise<void> {
  await api.delete(`/api/cliques/${cliqueId}/members/me`);
}

export async function removeMember(cliqueId: string, userId: string): Promise<void> {
  await api.delete(`/api/cliques/${cliqueId}/members/${userId}`);
}
