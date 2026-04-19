import { useQuery } from '@tanstack/react-query';
import { listNotifications } from '../../api/endpoints/notifications';

export function useUnreadNotificationCount(): number {
  const { data } = useQuery({
    queryKey: ['notifications'],
    queryFn: listNotifications,
    refetchInterval: 60_000,
    staleTime: 30_000,
  });
  return data?.filter((n) => !n.isRead).length ?? 0;
}
