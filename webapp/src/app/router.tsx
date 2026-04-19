import { createBrowserRouter } from 'react-router-dom';
import { AuthGuard } from '../auth/AuthGuard';
import { AppLayout } from './AppLayout';
import { LandingPage } from '../features/landing/LandingPage';
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
  // Public marketing surface. No auth check — shows "My Events →" in the nav
  // when already signed in instead of forcing a redirect.
  { path: '/', element: <LandingPage /> },

  // Public auth + invite routes.
  { path: '/login', element: <LoginScreen /> },
  { path: '/auth/callback', element: <AuthCallback /> },
  { path: '/invite/:code', element: <InviteAcceptScreen /> },

  // Auth-gated print route (outside the app shell because it has its own layout).
  {
    path: '/cliques/:id/invite/print',
    element: (
      <AuthGuard>
        <InvitePrintScreen />
      </AuthGuard>
    ),
  },

  // Authenticated app shell — pathless parent so children keep their full paths.
  {
    element: (
      <AuthGuard>
        <AppLayout />
      </AuthGuard>
    ),
    children: [
      { path: '/events', element: <EventsListScreen /> },
      { path: '/events/:id', element: <EventDetailScreen /> },
      { path: '/events/:id/messages', element: <MessagesScreen /> },
      { path: '/events/:id/messages/:threadId', element: <ThreadScreen /> },
      { path: '/cliques', element: <CliquesListScreen /> },
      { path: '/cliques/:id', element: <CliqueDetailScreen /> },
      { path: '/notifications', element: <NotificationsScreen /> },
      { path: '/profile', element: <ProfileScreen /> },
    ],
  },

  { path: '*', element: <NotFoundScreen /> },
]);
