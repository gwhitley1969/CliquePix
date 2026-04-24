import clsx from 'clsx';

/**
 * User avatar — renders an `<img>` inside a gradient-ring when `imageUrl`
 * (or `thumbUrl`) is present, otherwise falls back to initials. Ring
 * gradient is auto-hashed from the display name unless `framePreset`
 * (1..4) overrides it. `cacheBuster` is appended as `?v=<key>` so the
 * browser's HTTP cache invalidates when the user updates their avatar
 * but survives 1-hour SAS rotations.
 *
 * Matches the mobile AvatarWidget's palette 1:1 so the same user renders
 * the same gradient across platforms.
 */
export function Avatar({
  name,
  imageUrl,
  thumbUrl,
  framePreset,
  cacheBuster,
  size = 36,
  className,
}: {
  name: string | null | undefined;
  imageUrl?: string | null;
  thumbUrl?: string | null;
  framePreset?: number;
  cacheBuster?: string;
  size?: number;
  className?: string;
}) {
  const initials = getInitials(name);
  const gradient = gradientFor(name ?? '', framePreset);
  const ringWidth = Math.max(2, Math.round(size * 0.06));

  // Prefer the 128px thumb for card-size avatars; full original for the
  // profile hero (>= 64). 128px is 2x retina sharp for everything under
  // 64 — anything larger wants the 512px original.
  const effectiveUrl = size < 64 && thumbUrl ? thumbUrl : imageUrl;
  const finalUrl = effectiveUrl && cacheBuster
    ? appendCacheBuster(effectiveUrl, cacheBuster)
    : effectiveUrl;

  if (finalUrl) {
    return (
      <div
        className={clsx('flex-shrink-0 rounded-full', className)}
        style={{
          width: size,
          height: size,
          padding: ringWidth,
          background: gradient,
        }}
        aria-label={name ?? 'User'}
      >
        <img
          src={finalUrl}
          alt=""
          loading="lazy"
          className="w-full h-full rounded-full object-cover bg-white/10"
          style={{ display: 'block' }}
        />
      </div>
    );
  }

  return (
    <div
      className={clsx(
        'flex-shrink-0 rounded-full flex items-center justify-center font-semibold text-white select-none',
        className,
      )}
      style={{
        width: size,
        height: size,
        fontSize: Math.round(size * 0.38),
        background: gradient,
      }}
      aria-label={name ?? 'User'}
    >
      {initials}
    </div>
  );
}

function getInitials(name: string | null | undefined): string {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const palettes: string[] = [
  'linear-gradient(135deg, #00C2D1 0%, #2563EB 100%)',
  'linear-gradient(135deg, #2563EB 0%, #7C3AED 100%)',
  'linear-gradient(135deg, #7C3AED 0%, #EC4899 100%)',
  'linear-gradient(135deg, #00C2D1 0%, #7C3AED 100%)',
  'linear-gradient(135deg, #EC4899 0%, #00C2D1 100%)',
];

function gradientFor(name: string, preset?: number): string {
  // Preset 1..4 maps directly to palette indices 0..3 (preset 0 = auto).
  if (preset !== undefined && preset >= 1 && preset <= 4) {
    return palettes[preset - 1];
  }
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return palettes[hash % palettes.length];
}

function appendCacheBuster(url: string, key: string): string {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}_v=${encodeURIComponent(key)}`;
}
