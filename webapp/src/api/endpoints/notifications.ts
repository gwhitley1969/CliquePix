import { api } from '../client';
import type { AppNotification } from '../../models';

export async function listNotifications(): Promise<AppNotification[]> {
  const res = await api.get<{ data: AppNotification[] }>('/api/notifications');
  return res.data.data;
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
