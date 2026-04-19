import { useQuery } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';
import { ChevronLeft, MessageCircle } from 'lucide-react';
import { listEventThreads } from '../../api/endpoints/messages';
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

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <Link
        to={`/events/${id}`}
        className="inline-flex items-center gap-1 text-sm text-white/60 hover:text-white mb-4"
      >
        <ChevronLeft size={16} /> Back to event
      </Link>
      <h1 className="text-2xl font-bold mb-6">Messages</h1>
      {threads.isLoading ? (
        <LoadingSpinner />
      ) : !threads.data || threads.data.length === 0 ? (
        <EmptyState
          icon={MessageCircle}
          title="No messages yet"
          subtitle="Direct messages within this event will appear here."
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
