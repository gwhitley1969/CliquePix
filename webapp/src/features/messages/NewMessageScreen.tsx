import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, ChevronRight, Lock, Users } from 'lucide-react';
import { toast } from 'sonner';
import { listMembers } from '../../api/endpoints/cliques';
import { getEvent } from '../../api/endpoints/events';
import { createOrGetThread } from '../../api/endpoints/messages';
import { useAuthVerify } from '../auth/useAuthVerify';
import { Avatar } from '../../components/Avatar';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { EmptyState } from '../../components/EmptyState';
import { ErrorState } from '../../components/ErrorState';
import type { DmThread } from '../../models';

export function NewMessageScreen() {
  const { id: eventId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const me = useAuthVerify();
  const myId = me.data?.id;

  const eventQuery = useQuery({
    queryKey: ['event', eventId],
    queryFn: () => getEvent(eventId!),
    enabled: !!eventId,
  });
  const event = eventQuery.data;
  const expired = event?.status === 'expired';

  const membersQuery = useQuery({
    queryKey: ['clique', event?.cliqueId, 'members'],
    queryFn: () => listMembers(event!.cliqueId),
    enabled: !!event?.cliqueId && !expired,
  });

  const startMut = useMutation<DmThread, unknown, { userId: string }>({
    mutationFn: ({ userId }) => createOrGetThread(eventId!, userId),
    onSuccess: (thread) => {
      qc.invalidateQueries({ queryKey: ['event', eventId, 'threads'] });
      navigate(`/events/${eventId}/messages/${thread.id}`, { replace: true });
    },
    onError: () => toast.error('Could not start the conversation'),
  });
  const pendingUserId = startMut.isPending ? startMut.variables?.userId : undefined;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <Link
        to={`/events/${eventId}/messages`}
        className="inline-flex items-center gap-1 text-sm text-white/60 hover:text-white mb-4"
      >
        <ChevronLeft size={16} /> Back to messages
      </Link>
      <h1 className="text-2xl font-bold">New message</h1>
      {event?.name && (
        <p className="text-sm text-white/50 mt-1 mb-6">in {event.name}</p>
      )}

      {expired ? (
        <EmptyState
          icon={Lock}
          title="This event has ended"
          subtitle="You can read previous messages but can't start new conversations."
        />
      ) : eventQuery.isLoading || membersQuery.isLoading ? (
        <LoadingSpinner />
      ) : eventQuery.isError || membersQuery.isError ? (
        <ErrorState
          subtitle="We couldn't load the member list. Check your connection and try again."
          onRetry={() => {
            eventQuery.refetch();
            membersQuery.refetch();
          }}
        />
      ) : (() => {
        const others = (membersQuery.data ?? []).filter((m) => m.userId !== myId);
        if (others.length === 0) {
          return (
            <EmptyState
              icon={Users}
              title="Just you here"
              subtitle="Invite friends to your clique to start a conversation."
            />
          );
        }
        return (
          <ul className="space-y-1">
            {others.map((m) => {
              const isPending = pendingUserId === m.userId;
              return (
                <li key={m.userId}>
                  <button
                    type="button"
                    disabled={startMut.isPending}
                    onClick={() => startMut.mutate({ userId: m.userId })}
                    className="w-full flex items-center justify-between gap-3 p-3 rounded bg-dark-card border border-white/10 hover:border-aqua/50 disabled:opacity-50 disabled:cursor-not-allowed text-left"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <Avatar
                        size={36}
                        name={m.displayName}
                        imageUrl={m.avatarUrl}
                        thumbUrl={m.avatarThumbUrl}
                        framePreset={m.avatarFramePreset}
                        cacheBuster={m.avatarUpdatedAt ?? undefined}
                      />
                      <div className="min-w-0">
                        <div className="text-white truncate">{m.displayName}</div>
                        <div className="text-xs text-white/50">
                          {m.role === 'owner' ? 'Owner' : 'Member'}
                        </div>
                      </div>
                    </div>
                    {isPending ? (
                      <div className="w-4 h-4 rounded-full border-2 border-white/20 border-t-aqua animate-spin flex-shrink-0" />
                    ) : (
                      <ChevronRight size={16} className="text-white/40 flex-shrink-0" />
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        );
      })()}
    </div>
  );
}
