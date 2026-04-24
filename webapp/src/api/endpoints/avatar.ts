import { api } from '../client';
import type { User } from '../../models';

/**
 * Wrappers around the five avatar endpoints. Upload flow is two-step
 * (mirror of mobile): `getAvatarUploadUrl()` returns a short-lived SAS,
 * the client PUTs the compressed JPEG to that URL directly, then
 * `confirmAvatar()` asks the backend to generate the 128px thumbnail and
 * return the updated User (with signed read URLs).
 *
 * Response bodies go through the axios camelize interceptor, so we only
 * see camelCase on the client side even though the backend emits snake.
 */

export interface AvatarUploadSas {
  uploadUrl: string;
  blobPath: string;
}

export async function getAvatarUploadUrl(): Promise<AvatarUploadSas> {
  const res = await api.post<{ data: AvatarUploadSas }>('/api/users/me/avatar/upload-url');
  return res.data.data;
}

export async function confirmAvatar(): Promise<User> {
  const res = await api.post<{ data: User }>('/api/users/me/avatar');
  return res.data.data;
}

export async function deleteAvatar(): Promise<User> {
  const res = await api.delete<{ data: User }>('/api/users/me/avatar');
  return res.data.data;
}

export async function updateAvatarFrame(framePreset: number): Promise<User> {
  const res = await api.patch<{ data: User }>('/api/users/me/avatar/frame', {
    // Request body stays snake_case — backend validates on the original
    // snake form (per CLAUDE.md web client conventions).
    frame_preset: framePreset,
  });
  return res.data.data;
}

export type AvatarPromptAction = 'dismiss' | 'snooze';

export async function recordAvatarPrompt(action: AvatarPromptAction): Promise<User> {
  const res = await api.post<{ data: User }>('/api/users/me/avatar-prompt', {
    action,
  });
  return res.data.data;
}
