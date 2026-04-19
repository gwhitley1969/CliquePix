import { createBrowserRouter, Navigate } from 'react-router-dom';
import { AuthGuard } from '../auth/AuthGuard';
import { AppLayout } from './AppLayout';
import { LoginScreen } from '../features/auth/LoginScreen';
import { AuthCallback } from '../features/auth/AuthCallback';
import { EventsListScreen } from '../features/events/EventsListScreen';
import { EventDetailScreen } from '../features/events/EventDetailScreen';
import { CliquesListScreen } from '../features/cliques/CliquesListScreen';
import { CliqueDetailScreen } from '../features/cliques/CliqueDetailScreen';
import { InvitePrintScreen } from '../features/cliques/InvitePrintScreen';
import { InviteAcceptScreen } from '../features/cliques/InviteAcceptScreen';
import { MessagesScreen } from '../features/messages/MessagesScreen';
import { ThreadScreen } from '../features/messages/ThreadScreen';
import { NotificationsScreen } from '../features/notifications/NotificationsScreen';
import { ProfileScreen } from '../features/profile/ProfileScreen';
import { NotFoundScreen } from './NotFoundScreen';

export const router = createBrowserRouter([
  {
    path: '/login',
    element: <LoginScreen />,
  },
  {
    path: '/auth/callback',
    element: <AuthCallback />,
  },
  {
    path: '/invite/:code',
    element: <InviteAcceptScreen />,
  },
  {
    path: '/cliques/:id/invite/print',
    element: (
      <AuthGuard>
        <InvitePrintScreen />
      </AuthGuard>
    ),
  },
  {
    path: '/',
    element: (
      <AuthGuard>
        <AppLayout />
      </AuthGuard>
    ),
    children: [
      { index: true, element: <Navigate to="/events" replace /> },
      { path: 'events', element: <EventsListScreen /> },
      { path: 'events/:id', element: <EventDetailScreen /> },
      { path: 'events/:id/messages', element: <MessagesScreen /> },
      { path: 'events/:id/messages/:threadId', element: <ThreadScreen /> },
      { path: 'cliques', element: <CliquesListScreen /> },
      { path: 'cliques/:id', element: <CliqueDetailScreen /> },
      { path: 'notifications', element: <NotificationsScreen /> },
      { path: 'profile', element: <ProfileScreen /> },
    ],
  },
  { path: '*', element: <NotFoundScreen /> },
]);
