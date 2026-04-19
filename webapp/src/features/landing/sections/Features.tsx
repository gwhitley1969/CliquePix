import {
  Camera,
  Film,
  Heart,
  QrCode,
  Timer,
  Laptop,
  type LucideIcon,
} from 'lucide-react';
import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

const FEATURES: { icon: LucideIcon; title: string; body: string }[] = [
  {
    icon: Camera,
    title: 'In-app camera + editor',
    body: 'Crop, draw, stickers, filters — right where you are. No app-switching.',
  },
  {
    icon: Film,
    title: 'Video, done right',
    body: '1080p streaming via HLS. Instant preview while it transcodes. MP4 fallback on any connection.',
  },
  {
    icon: Heart,
    title: 'Reactions + event DMs',
    body: '❤️ 😂 🔥 😮 on every card. Private 1:1 chat scoped to the event itself.',
  },
  {
    icon: QrCode,
    title: 'QR invites',
    body: 'Print a branded invite card for wedding tables or event sign-ins. Guests scan and join in seconds.',
  },
  {
    icon: Timer,
    title: 'Auto-delete',
    body: 'Pick 24 hours, 3 days, or a week. The cloud cleans up on time so your storage stays yours.',
  },
  {
    icon: Laptop,
    title: 'Everywhere you are',
    body: 'iOS, Android, and the web. Same Clique, same photos, same moments — whichever screen is closer.',
  },
];

export function Features() {
  const { ref, revealed } = useRevealOnScroll<HTMLDivElement>();
  return (
    <section className="bg-dark-bg">
      <div className="max-w-6xl mx-auto px-4 md:px-8 py-16 md:py-24">
        <div
          ref={ref}
          className={`transition-all duration-700 ${
            revealed ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
          }`}
        >
          <div className="max-w-2xl mb-10 md:mb-14">
            <h2 className="text-3xl md:text-4xl font-bold text-white">
              Everything you'd actually use
            </h2>
            <p className="mt-3 text-white/60">
              No bloat, no ads, no algorithm. Just the features that make sharing with your
              people feel natural.
            </p>
          </div>

          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
            {FEATURES.map((feature) => (
              <div
                key={feature.title}
                className="rounded-xl bg-dark-card border border-white/10 p-6 hover:border-aqua/30 transition-colors"
              >
                <div className="w-10 h-10 rounded-lg bg-gradient-primary flex items-center justify-center mb-4 shadow-lg shadow-deepBlue/20">
                  <feature.icon size={20} className="text-white" />
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">{feature.title}</h3>
                <p className="text-sm text-white/60 leading-relaxed">{feature.body}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
