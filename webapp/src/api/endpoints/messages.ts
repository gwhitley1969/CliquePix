import { api } from '../client';
import type { DmMessage, DmThread } from '../../models';

export async function listEventThreads(eventId: string): Promise<DmThread[]> {
  const res = await api.get<{ data: DmThread[] }>(`/api/events/${eventId}/dm-threads`);
  return res.data.data;
}

export async function createOrGetThread(
  eventId: string,
  recipientUserId: string,
): Promise<DmThread> {
  const res = await api.post<{ data: DmThread }>(`/api/events/${eventId}/dm-threads`, {
    recipient_user_id: recipientUserId,
  });
  return res.data.data;
}

export async function getThread(threadId: string): Promise<DmThread> {
  const res = await api.get<{ data: DmThread }>(`/api/dm-threads/${threadId}`);
  return res.data.data;
}

export async function listThreadMessages(threadId: string): Promise<DmMessage[]> {
  // Backend envelope: { data: { messages: [...], nextCursor: string|null } }
  const res = await api.get<{
    data: { messages: DmMessage[]; nextCursor?: string | null };
  }>(`/api/dm-threads/${threadId}/messages`);
  return res.data.data.messages ?? [];
}

export async function sendMessage(threadId: string, body: string): Promise<DmMessage> {
  const res = await api.post<{ data: DmMessage }>(`/api/dm-threads/${threadId}/messages`, {
    body,
  });
  return res.data.data;
}

export async function markThreadRead(threadId: string): Promise<void> {
  await api.patch(`/api/dm-threads/${threadId}/read`);
}

export async function negotiateRealtime(): Promise<{ url: string }> {
  const res = await api.post<{ data: { url: string } }>('/api/realtime/dm/negotiate');
  return res.data.data;
}
