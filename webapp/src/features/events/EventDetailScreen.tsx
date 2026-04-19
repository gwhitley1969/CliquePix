import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useState } from 'react';
import { toast } from 'sonner';
import { ChevronLeft, MessageCircle, Trash2 } from 'lucide-react';
import { deleteEvent, getEvent } from '../../api/endpoints/events';
import { listEventPhotos } from '../../api/endpoints/photos';
import { listEventVideos } from '../../api/endpoints/videos';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { ErrorState } from '../../components/ErrorState';
import { formatCountdown } from '../../lib/formatDate';
import { MediaFeed } from '../photos/MediaFeed';
import { MediaUploader } from '../photos/MediaUploader';
import type { Media } from '../../models';

export function EventDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [confirmDelete, setConfirmDelete] = useState(false);

  const eventQuery = useQuery({
    queryKey: ['event', id],
    queryFn: () => getEvent(id!),
    enabled: !!id,
  });

  const photosQuery = useQuery({
    queryKey: ['event', id, 'photos'],
    queryFn: () => listEventPhotos(id!),
    enabled: !!id,
  });

  const videosQuery = useQuery({
    queryKey: ['event', id, 'videos'],
    queryFn: () => listEventVideos(id!),
    enabled: !!id,
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteEvent(id!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['events'] });
      toast.success('Event deleted');
      navigate('/events');
    },
    onError: () => toast.error('Failed to delete event'),
  });

  if (eventQuery.isLoading) return <LoadingSpinner />;
  if (eventQuery.isError) {
    return (
      <ErrorState
        title="Couldn't load this event"
        subtitle="We couldn't reach the server. Check your connection and try again."
        onRetry={() => eventQuery.refetch()}
      />
    );
  }
  if (!eventQuery.data) return <div className="p-6 text-white/60">Event not found.</div>;

  const event = eventQuery.data;
  const media: Media[] = [
    ...(photosQuery.data ?? []),
    ...(videosQuery.data ?? []),
  ].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      <Link
        to="/events"
        className="inline-flex items-center gap-1 text-sm text-white/60 hover:text-white mb-4"
      >
        <ChevronLeft size={16} /> Back
      </Link>

      <div className="flex items-start justify-between gap-4 mb-6">
        <div>
          <div className="text-xs uppercase tracking-wide text-aqua">{event.cliqueName}</div>
          <h1 className="text-2xl font-bold">{event.name}</h1>
          {event.description && <p className="text-white/60 mt-1">{event.description}</p>}
          <p className="text-sm text-white/50 mt-2">{formatCountdown(event.expiresAt)}</p>
        </div>
        <div className="flex flex-col gap-2 items-end">
          <Link
            to={`/events/${event.id}/messages`}
            className="inline-flex items-center gap-1 text-sm text-white/70 hover:text-white"
          >
            <MessageCircle size={16} /> Messages
          </Link>
          <button
            onClick={() => setConfirmDelete(true)}
            className="inline-flex items-center gap-1 text-sm text-white/50 hover:text-error"
          >
            <Trash2 size={16} /> Delete
          </button>
        </div>
      </div>

      <MediaUploader eventId={event.id} />

      <div className="mt-8">
        {media.length === 0 ? (
          <div className="text-center py-12 text-white/50 text-sm">
            No photos or videos yet. Drop some above to start.
          </div>
        ) : (
          <MediaFeed media={media} />
        )}
      </div>

      <ConfirmDestructive
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title="Delete this event?"
        message="All photos and videos will be permanently removed from the cloud. Clique members will be notified. This cannot be undone."
        confirmLabel="Delete event"
        onConfirm={() => deleteMutation.mutate()}
        loading={deleteMutation.isPending}
      />
    </div>
  );
}
