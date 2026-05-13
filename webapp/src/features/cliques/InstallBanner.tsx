import { useEffect } from 'react';
import { PlayStoreBadge } from '../landing/components/PlayStoreBadge';
import { trackEvent } from '../../lib/ai';
import type { Platform } from '../../lib/platform';

const ANDROID_APP_ID = 'com.cliquepix.clique_pix';

function buildPlayStoreUrl(inviteCode: string): string {
  const referrer = encodeURIComponent(`invite_code=${inviteCode}`);
  return `https://play.google.com/store/apps/details?id=${ANDROID_APP_ID}&referrer=${referrer}`;
}

export function InstallBanner({ inviteCode, platform }: { inviteCode: string; platform: Platform }) {
  useEffect(() => {
    if (platform !== 'ios') {
      trackEvent('web_invite_install_banner_shown', { platform });
    }
  }, [platform]);

  if (platform === 'ios') return null;

  const playStoreUrl = buildPlayStoreUrl(inviteCode);

  return (
    <div className="mb-6 rounded-2xl border border-white/10 bg-white/[0.03] p-5 text-left">
      <h2 className="text-base font-semibold text-white">Get the full Clique Pix experience</h2>
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
        <PlayStoreBadge
          href={playStoreUrl}
          onClick={() => trackEvent('web_invite_install_badge_clicked', { platform: 'android' })}
        />
      </div>
    </div>
  );
}
