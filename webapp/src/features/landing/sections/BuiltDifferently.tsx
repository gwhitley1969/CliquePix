import { Lock, Clock, Users, HardDrive, type LucideIcon } from 'lucide-react';
import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

const POINTS: { icon: LucideIcon; title: string; body: string }[] = [
  {
    icon: Lock,
    title: 'Private by default',
    body: 'No followers. No public feed. No algorithm deciding who sees your photos. You decide.',
  },
  {
    icon: Clock,
    title: 'Temporary by design',
    body: "Photos live for the event, not forever. Your memories don't become someone else's dataset.",
  },
  {
    icon: Users,
    title: 'Small groups, not audiences',
    body: "Cliques are the people you choose — every time. You're not broadcasting. You're sharing.",
  },
  {
    icon: HardDrive,
    title: 'Your memories, your device',
    body: "Save anything you want to your phone or computer. The cloud clears out the rest.",
  },
];

export function BuiltDifferently() {
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
            <h2 className="text-3xl md:text-4xl font-bold text-white">Built differently</h2>
            <p className="mt-3 text-white/60">
              Photo apps optimize for scrolling, likes, and reach. Clique Pix is built for the
              opposite: real moments, real people, then out of your way.
            </p>
          </div>

          <div className="grid sm:grid-cols-2 gap-5">
            {POINTS.map((point) => (
              <div
                key={point.title}
                className="flex gap-4 rounded-xl bg-dark-card border border-white/10 p-6"
              >
                <div className="w-10 h-10 rounded-lg bg-gradient-primary flex items-center justify-center flex-shrink-0 shadow-md">
                  <point.icon size={18} className="text-white" />
                </div>
                <div>
                  <h3 className="text-lg font-semibold text-white mb-1.5">{point.title}</h3>
                  <p className="text-sm text-white/60 leading-relaxed">{point.body}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
