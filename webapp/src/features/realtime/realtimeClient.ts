import { WebPubSubClient } from '@azure/web-pubsub-client';
import { QueryClient } from '@tanstack/react-query';
import { negotiateRealtime } from '../../api/endpoints/messages';
import { trackEvent } from '../../lib/ai';

let client: WebPubSubClient | null = null;
let queryClient: QueryClient | null = null;

export function setRealtimeQueryClient(qc: QueryClient) {
  queryClient = qc;
}

export async function initRealtime(): Promise<void> {
  if (client) return;
  try {
    client = new WebPubSubClient({
      getClientAccessUrl: async () => {
        const { url } = await negotiateRealtime();
        return url;
      },
    });

    client.on('group-message', (e) => handleMessage(e.message.data));
    client.on('server-message', (e) => handleMessage(e.message.data));

    await client.start();
    trackEvent('web_dm_realtime_connected');
  } catch (err) {
    console.error('realtime init failed', err);
  }
}

function handleMessage(data: unknown) {
  if (!data || typeof data !== 'object' || !queryClient) return;
  const event = data as { type?: string; thread_id?: string; event_id?: string };
  switch (event.type) {
    case 'dm_message_created':
      if (event.thread_id) {
        queryClient.invalidateQueries({ queryKey: ['thread', event.thread_id, 'messages'] });
      }
      break;
    case 'video_ready':
      if (event.event_id) {
        queryClient.invalidateQueries({ queryKey: ['event', event.event_id, 'videos'] });
      }
      break;
    case 'notification_created':
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
      break;
  }
}

export function teardownRealtime() {
  if (client) {
    client.stop();
    client = null;
  }
}
