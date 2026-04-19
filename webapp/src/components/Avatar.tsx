import clsx from 'clsx';

/**
 * Initials avatar. Matches the mobile app's AvatarWidget — gradient background
 * derived from the first letter so the same person always renders the same color.
 */
export function Avatar({
  name,
  size = 36,
  className,
}: {
  name: string | null | undefined;
  size?: number;
  className?: string;
}) {
  const initials = getInitials(name);
  const gradient = gradientForName(name ?? '');
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
  'linear-gradient(135deg, #EC4899 0%, #F59E0B 100%)',
  'linear-gradient(135deg, #16A34A 0%, #00C2D1 100%)',
];

function gradientForName(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return palettes[hash % palettes.length];
}
