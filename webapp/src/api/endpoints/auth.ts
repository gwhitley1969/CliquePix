import { api } from '../client';
import type { User } from '../../models';

export async function verifyAuth(): Promise<User> {
  const res = await api.post<{ data: User }>('/api/auth/verify');
  return res.data.data;
}

export async function getMe(): Promise<User> {
  const res = await api.get<{ data: User }>('/api/users/me');
  return res.data.data;
}

export async function deleteAccount(): Promise<void> {
  await api.delete('/api/users/me');
}
