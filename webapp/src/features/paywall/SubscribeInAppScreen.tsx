import { useMsal } from '@azure/msal-react';
import { AppStoreBadge } from '../landing/components/AppStoreBadge';
import { PlayStoreBadge } from '../landing/components/PlayStoreBadge';

const PLAY_URL =
  'https://play.google.com/store/apps/details?id=com.cliquepix.clique_pix';

/** Shown to authenticated web users without effective access (trial lapsed,
 *  unsubscribed). No web purchase flow in v1 — point them at the mobile app. */
export function SubscribeInAppScreen() {
  const { instance } = useMsal();
  return (
    <div className="min-h-screen bg-dark-bg flex flex-col items-center justify-center px-6 text-center text-white">
      <div className="max-w-md w-full rounded-lg bg-dark-card border border-white/10 p-8">
        <div className="mx-auto mb-5 h-14 w-14 rounded-2xl bg-gradient-primary" />
        <h1 className="text-2xl font-bold mb-2">Clique Pix Plus</h1>
        <p className="text-white/70 mb-6">
          Your free trial has ended. Subscribe in the Clique Pix mobile app to
          keep sharing — your subscription unlocks the app everywhere, including
          here on the web.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3 mb-8">
          <AppStoreBadge />
          <PlayStoreBadge href={PLAY_URL} />
        </div>
        <button
          className="text-sm text-white/50 hover:text-white/80"
          onClick={() =>
            instance
              .logoutRedirect({ postLogoutRedirectUri: '/' })
              .catch(console.error)
          }
        >
          Sign out
        </button>
        <div className="mt-6 text-xs text-white/40 space-x-3">
          <a href="/docs/privacy" className="hover:underline">
            Privacy Policy
          </a>
          <span>·</span>
          <a href="/docs/terms" className="hover:underline">
            Terms of Service
          </a>
        </div>
      </div>
    </div>
  );
}
