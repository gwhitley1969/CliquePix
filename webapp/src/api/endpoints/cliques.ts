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

export async function getInvite(
  cliqueId: string,
): Promise<{ invite_code: string; invite_url: string }> {
  const res = await api.post<{ data: { invite_code: string; invite_url: string } }>(
    `/api/cliques/${cliqueId}/invite`,
  );
  return res.data.data;
}

export async function joinCliqueByCode(inviteCode: string): Promise<Clique> {
  const res = await api.post<{ data: Clique }>(`/api/cliques/join`, {
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
