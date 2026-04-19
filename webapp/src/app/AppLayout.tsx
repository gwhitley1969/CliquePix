import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useMsal } from '@azure/msal-react';
import { Bell, Calendar, LogOut, User, Users } from 'lucide-react';
import { useEffect } from 'react';
import { useAuthVerify } from '../features/auth/useAuthVerify';
import { useUnreadNotificationCount } from '../features/notifications/useUnreadNotificationCount';
import { initRealtime, teardownRealtime } from '../features/realtime/realtimeClient';
import { trackEvent } from '../lib/ai';

const navItems = [
  { to: '/events', label: 'Events', icon: Calendar },
  { to: '/cliques', label: 'Cliques', icon: Users },
  { to: '/notifications', label: 'Notifications', icon: Bell },
  { to: '/profile', label: 'Profile', icon: User },
];

export function AppLayout() {
  useAuthVerify();
  const { instance, accounts } = useMsal();
  const unread = useUnreadNotificationCount();
  const navigate = useNavigate();
  const displayName = accounts[0]?.name ?? accounts[0]?.username ?? 'Signed in';

  useEffect(() => {
    initRealtime();
    trackEvent('web_login_success');
    return () => teardownRealtime();
  }, []);

  const onSignOut = () => {
    instance.logoutRedirect({ postLogoutRedirectUri: '/' }).catch(console.error);
  };

  return (
    <div className="min-h-full flex flex-col md:flex-row">
      <header className="md:hidden flex items-center justify-between px-4 py-3 bg-dark-surface border-b border-white/10">
        <span className="text-lg font-bold bg-gradient-primary bg-clip-text text-transparent">
          Clique Pix
        </span>
        <button
          onClick={() => navigate('/notifications')}
          className="relative p-2"
          aria-label="Notifications"
        >
          <Bell size={20} />
          {unread > 0 && (
            <span className="absolute top-1 right-1 bg-pink text-white text-xs rounded-full w-4 h-4 flex items-center justify-center">
              {unread > 9 ? '9+' : unread}
            </span>
          )}
        </button>
      </header>

      <aside className="hidden md:flex md:w-56 flex-col bg-dark-surface border-r border-white/10 py-6 px-3">
        <div className="px-3 pb-6">
          <span className="text-xl font-bold bg-gradient-primary bg-clip-text text-transparent">
            Clique Pix
          </span>
        </div>
        <nav className="flex-1 space-y-1">
          {navItems.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2 rounded transition-colors relative ${
                  isActive
                    ? 'bg-dark-card text-white'
                    : 'text-white/60 hover:text-white hover:bg-dark-card/50'
                }`
              }
            >
              <Icon size={18} />
              <span className="text-sm">{label}</span>
              {to === '/notifications' && unread > 0 && (
                <span className="ml-auto bg-pink text-white text-xs rounded-full px-2 py-0.5">
                  {unread > 9 ? '9+' : unread}
                </span>
              )}
            </NavLink>
          ))}
        </nav>
        <div className="px-3 py-3 border-t border-white/10 text-sm">
          <div className="text-white/80 truncate">{displayName}</div>
          <button
            onClick={onSignOut}
            className="mt-2 text-white/50 hover:text-white flex items-center gap-2"
          >
            <LogOut size={14} /> Sign out
          </button>
        </div>
      </aside>

      <main className="flex-1 overflow-auto pb-20 md:pb-0">
        <Outlet />
      </main>

      <nav className="md:hidden fixed bottom-0 inset-x-0 bg-dark-surface border-t border-white/10 flex">
        {navItems.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `flex-1 flex flex-col items-center py-2 text-xs gap-1 ${
                isActive ? 'text-white' : 'text-white/50'
              }`
            }
          >
            <Icon size={18} />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
