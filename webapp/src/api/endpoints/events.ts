import { api } from '../client';
import type { CliqueEvent } from '../../models';

export async function listAllEvents(): Promise<CliqueEvent[]> {
  const res = await api.get<{ data: CliqueEvent[] }>('/api/events');
  return res.data.data;
}

export async function listCliqueEvents(cliqueId: string): Promise<CliqueEvent[]> {
  const res = await api.get<{ data: CliqueEvent[] }>(`/api/cliques/${cliqueId}/events`);
  return res.data.data;
}

export async function getEvent(eventId: string): Promise<CliqueEvent> {
  const res = await api.get<{ data: CliqueEvent }>(`/api/events/${eventId}`);
  return res.data.data;
}

export async function createEvent(input: {
  cliqueId: string;
  name: string;
  description?: string;
  retentionHours: 24 | 72 | 168;
}): Promise<CliqueEvent> {
  const res = await api.post<{ data: CliqueEvent }>(
    `/api/cliques/${input.cliqueId}/events`,
    {
      name: input.name,
      description: input.description ?? null,
      retention_hours: input.retentionHours,
    },
  );
  return res.data.data;
}

export async function deleteEvent(eventId: string): Promise<void> {
  await api.delete(`/api/events/${eventId}`);
}
