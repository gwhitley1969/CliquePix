import { useEffect } from 'react';
import { PlayStoreBadge } from '../landing/components/PlayStoreBadge';
import { AppStoreBadge } from '../landing/components/AppStoreBadge';
import { trackEvent } from '../../lib/ai';
import type { Platform } from '../../lib/platform';

const ANDROID_APP_ID = 'com.cliquepix.clique_pix';
const APP_STORE_URL = 'https://apps.apple.com/us/app/clique-pix-group-pic-sharing/id6766294274';

function buildPlayStoreUrl(inviteCode: string): string {
  const referrer = encodeURIComponent(`invite_code=${inviteCode}`);
  return `https://play.google.com/store/apps/details?id=${ANDROID_APP_ID}&referrer=${referrer}`;
}

export function InstallBanner({ inviteCode, platform }: { inviteCode: string; platform: Platform }) {
  useEffect(() => {
    trackEvent('web_invite_install_banner_shown', { platform });
  }, [platform]);

  const playStoreUrl = buildPlayStoreUrl(inviteCode);

  return (
    <div className="mb-6 rounded-2xl border border-white/10 bg-white/[0.03] p-5 text-left">
      <h2 className="text-base font-semibold text-white">Get the full CLIQUE Pix experience</h2>
      <ul className="mt-3 space-y-1.5 text-sm text-white/70">
        <li className="flex gap-2">
          <span className="text-aqua">•</span> In-app camera + photo editor
        </li>
        <li className="flex gap-2">
          <span className="text-aqua">•</span> Push notifications when new photos and videos arrive
        </li>
        <li className="flex gap-2">
          <span className="text-aqua">•</span> Save photos and videos to your camera roll
        </li>
        <li className="flex gap-2">
          <span className="text-aqua">•</span> Full HD video playback
        </li>
      </ul>
      <div className="mt-5 flex flex-wrap items-center gap-3">
        {platform === 'ios' ? (
          <AppStoreBadge
            href={APP_STORE_URL}
            onClick={() => trackEvent('web_invite_install_badge_clicked', { platform: 'ios' })}
          />
        ) : (
          <PlayStoreBadge
            href={playStoreUrl}
            onClick={() => trackEvent('web_invite_install_badge_clicked', { platform: 'android' })}
          />
        )}
      </div>
    </div>
  );
}
