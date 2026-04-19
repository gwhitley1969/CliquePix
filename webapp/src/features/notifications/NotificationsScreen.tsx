import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Bell, Camera, Film, UserPlus, Clock, Trash2, type LucideIcon } from 'lucide-react';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import {
  clearAllNotifications,
  listNotifications,
  markNotificationRead,
} from '../../api/endpoints/notifications';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { EmptyState } from '../../components/EmptyState';
import { ErrorState } from '../../components/ErrorState';
import { Button } from '../../components/Button';
import { formatRelative } from '../../lib/formatDate';
import type { AppNotification, NotificationType } from '../../models';

const iconFor: Record<NotificationType, LucideIcon> = {
  new_photo: Camera,
  new_video: Film,
  video_ready: Film,
  event_expiring: Clock,
  event_expired: Clock,
  member_joined: UserPlus,
  event_deleted: Clock,
  dm_message: Bell,
};

export function NotificationsScreen() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['notifications'],
    queryFn: listNotifications,
    refetchInterval: 60_000,
  });

  const clearMut = useMutation({
    mutationFn: clearAllNotifications,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['notifications'] });
      toast.success('Notifications cleared');
    },
  });

  const onTap = (n: AppNotification) => {
    markNotificationRead(n.id).then(() =>
      qc.invalidateQueries({ queryKey: ['notifications'] }),
    );
    const payload = n.payloadJson as { eventId?: string; cliqueId?: string; threadId?: string };
    if (payload.threadId && payload.eventId) {
      navigate(`/events/${payload.eventId}/messages/${payload.threadId}`);
    } else if (payload.eventId) {
      navigate(`/events/${payload.eventId}`);
    } else if (payload.cliqueId) {
      navigate(`/cliques/${payload.cliqueId}`);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Notifications</h1>
        {data && data.length > 0 && (
          <Button
            variant="ghost"
            onClick={() => clearMut.mutate()}
            disabled={clearMut.isPending}
          >
            <Trash2 size={16} className="mr-1" /> Clear all
          </Button>
        )}
      </div>
      {isLoading ? (
        <LoadingSpinner />
      ) : isError ? (
        <ErrorState
          title="Couldn't load notifications"
          subtitle="We couldn't reach the server. Check your connection and try again."
          onRetry={() => refetch()}
        />
      ) : !data || data.length === 0 ? (
        <EmptyState
          icon={Bell}
          title="No notifications"
          subtitle="When someone posts or something happens in your cliques, it'll show up here."
        />
      ) : (
        <ul className="space-y-1">
          {data.map((n) => {
            const Icon = iconFor[n.type] ?? Bell;
            return (
              <li key={n.id}>
                <button
                  onClick={() => onTap(n)}
                  className={`w-full text-left flex gap-3 p-3 rounded transition-colors ${
                    n.isRead
                      ? 'bg-dark-card/40 hover:bg-dark-card'
                      : 'bg-dark-card hover:bg-dark-card/70'
                  }`}
                >
                  <div className="w-9 h-9 rounded-full bg-dark-bg flex items-center justify-center text-aqua flex-shrink-0">
                    <Icon size={16} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium text-white">{n.title}</div>
                    {n.subtitle && (
                      <div className="text-xs text-white/60 truncate">{n.subtitle}</div>
                    )}
                    <div className="text-xs text-white/40 mt-1">
                      {formatRelative(n.createdAt)}
                    </div>
                  </div>
                  {!n.isRead && (
                    <span className="w-2 h-2 bg-aqua rounded-full mt-2 flex-shrink-0" />
                  )}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
