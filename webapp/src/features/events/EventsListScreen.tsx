import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useState } from 'react';
import { Calendar, Plus } from 'lucide-react';
import { listAllEvents } from '../../api/endpoints/events';
import { Button } from '../../components/Button';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { EmptyState } from '../../components/EmptyState';
import { ErrorState } from '../../components/ErrorState';
import { formatCountdown } from '../../lib/formatDate';
import { CreateEventModal } from './CreateEventModal';

export function EventsListScreen() {
  const [createOpen, setCreateOpen] = useState(false);
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['events'],
    queryFn: listAllEvents,
  });

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Events</h1>
        <Button onClick={() => setCreateOpen(true)}>
          <Plus size={16} className="mr-1" /> New Event
        </Button>
      </div>

      {isLoading ? (
        <LoadingSpinner />
      ) : isError ? (
        <ErrorState
          title="Couldn't load events"
          subtitle="We couldn't reach the server. Check your connection and try again."
          onRetry={() => refetch()}
        />
      ) : !data || data.length === 0 ? (
        <EmptyState
          icon={Calendar}
          title="No events yet"
          subtitle="Create your first event to start sharing photos and videos with your Clique."
          action={<Button onClick={() => setCreateOpen(true)}>Create Event</Button>}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {data.map((event) => (
            <Link
              key={event.id}
              to={`/events/${event.id}`}
              className="block p-4 rounded-lg bg-dark-card border border-white/10 hover:border-aqua/50 transition-colors"
            >
              <div className="text-xs uppercase tracking-wide text-aqua mb-1">
                {event.cliqueName ?? 'Event'}
              </div>
              <div className="text-lg font-semibold mb-2">{event.name}</div>
              <div className="flex items-center justify-between text-sm text-white/60">
                <span>
                  {(event.photoCount ?? 0) + (event.videoCount ?? 0)} items
                </span>
                <span>{formatCountdown(event.expiresAt)}</span>
              </div>
            </Link>
          ))}
        </div>
      )}

      <CreateEventModal open={createOpen} onOpenChange={setCreateOpen} />
    </div>
  );
}
