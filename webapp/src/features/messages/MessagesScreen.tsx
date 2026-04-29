import { useQuery } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { ChevronLeft, MessageCircle, Plus } from 'lucide-react';
import { listEventThreads } from '../../api/endpoints/messages';
import { getEvent } from '../../api/endpoints/events';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { EmptyState } from '../../components/EmptyState';
import { formatRelative } from '../../lib/formatDate';

export function MessagesScreen() {
  const { id } = useParams<{ id: string }>();
  const threads = useQuery({
    queryKey: ['event', id, 'threads'],
    queryFn: () => listEventThreads(id!),
    enabled: !!id,
  });
  const eventQuery = useQuery({
    queryKey: ['event', id],
    queryFn: () => getEvent(id!),
    enabled: !!id,
  });
  const canStartNew = eventQuery.data?.status !== 'expired';
  const newMessageHref = `/events/${id}/messages/new`;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <Link
        to={`/events/${id}`}
        className="inline-flex items-center gap-1 text-sm text-white/60 hover:text-white mb-4"
      >
        <ChevronLeft size={16} /> Back to event
      </Link>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Messages</h1>
        {canStartNew && threads.data && threads.data.length > 0 && (
          <Link
            to={newMessageHref}
            className="inline-flex items-center gap-1 rounded bg-gradient-primary px-3 py-1.5 text-sm font-medium text-white hover:opacity-90 active:opacity-80 transition-opacity"
          >
            <Plus size={16} /> New message
          </Link>
        )}
      </div>
      {threads.isLoading ? (
        <LoadingSpinner />
      ) : !threads.data || threads.data.length === 0 ? (
        <EmptyState
          icon={MessageCircle}
          title="No messages yet"
          subtitle="Direct messages within this event will appear here."
          action={
            canStartNew ? (
              <Link
                to={newMessageHref}
                className="inline-flex items-center gap-1 rounded bg-gradient-primary px-4 py-2 text-sm font-medium text-white hover:opacity-90 active:opacity-80 transition-opacity"
              >
                <Plus size={16} /> Start a conversation
              </Link>
            ) : undefined
          }
        />
      ) : (
        <ul className="space-y-2">
          {threads.data.map((t) => (
            <li key={t.id}>
              <Link
                to={`/events/${id}/messages/${t.id}`}
                className="block p-3 rounded bg-dark-card border border-white/10 hover:border-aqua/50"
              >
                <div className="flex items-center justify-between">
                  <div className="font-medium">{t.otherUser.displayName}</div>
                  {t.unreadCount > 0 && (
                    <span className="bg-pink text-white text-xs rounded-full px-2 py-0.5">
                      {t.unreadCount}
                    </span>
                  )}
                </div>
                {t.lastMessage && (
                  <div className="text-sm text-white/60 truncate mt-1">
                    {t.lastMessage.body}
                  </div>
                )}
                {t.lastMessage && (
                  <div className="text-xs text-white/40 mt-1">
                    {formatRelative(t.lastMessage.createdAt)}
                  </div>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
