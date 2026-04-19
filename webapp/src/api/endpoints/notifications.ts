import { api } from '../client';
import type { AppNotification } from '../../models';

export async function listNotifications(): Promise<AppNotification[]> {
  // Backend envelope: { data: { notifications: [...], nextCursor: string|null } }
  // (nextCursor is post-camelize from next_cursor)
  const res = await api.get<{ data: { notifications: AppNotification[]; nextCursor?: string | null } }>(
    '/api/notifications',
  );
  return res.data.data.notifications ?? [];
}

export async function markNotificationRead(id: string): Promise<void> {
  await api.patch(`/api/notifications/${id}/read`);
}

export async function deleteNotification(id: string): Promise<void> {
  await api.delete(`/api/notifications/${id}`);
}

export async function clearAllNotifications(): Promise<void> {
  await api.delete('/api/notifications');
}
