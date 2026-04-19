import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

const CASES = [
  {
    emoji: '💍',
    title: 'Weddings',
    body: 'Every guest, every angle. Printable QR cards for reception tables mean the photos come to you, not the other way around.',
    tint: 'from-pink/20 via-violet/15 to-transparent',
  },
  {
    emoji: '✈️',
    title: 'Trips & travel',
    body: 'Shared camera roll for the friends you actually traveled with. No more "send me that one from Tuesday."',
    tint: 'from-aqua/20 via-deepBlue/15 to-transparent',
  },
  {
    emoji: '🎉',
    title: 'Parties & milestones',
    body: 'Birthdays, bachelor/ette nights, game nights, graduation. Capture it together, skip the group-text chaos.',
    tint: 'from-violet/20 via-pink/15 to-transparent',
  },
  {
    emoji: '👨‍👩‍👧',
    title: 'Family gatherings',
    body: "Grandma's 80th. The reunion. Holiday mornings. Everyone contributes, everyone gets the good ones.",
    tint: 'from-deepBlue/20 via-aqua/15 to-transparent',
  },
];

export function UseCases() {
  const { ref, revealed } = useRevealOnScroll<HTMLDivElement>();
  return (
    <section className="bg-dark-surface border-y border-white/5">
      <div className="max-w-6xl mx-auto px-4 md:px-8 py-16 md:py-24">
        <div
          ref={ref}
          className={`transition-all duration-700 ${
            revealed ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
          }`}
        >
          <div className="max-w-2xl mb-10 md:mb-14">
            <h2 className="text-3xl md:text-4xl font-bold text-white">
              Perfect for the moments that matter
            </h2>
            <p className="mt-3 text-white/60">
              Anywhere you'd make a small group chat just to share photos — Clique Pix is
              already better.
            </p>
          </div>

          <div className="grid sm:grid-cols-2 gap-5">
            {CASES.map((useCase) => (
              <div
                key={useCase.title}
                className="relative rounded-xl bg-dark-card border border-white/10 p-6 overflow-hidden"
              >
                <div
                  aria-hidden="true"
                  className={`absolute inset-0 bg-gradient-to-br ${useCase.tint} pointer-events-none opacity-70`}
                />
                <div className="relative">
                  <div className="text-4xl mb-3 leading-none">{useCase.emoji}</div>
                  <h3 className="text-xl font-semibold text-white mb-2">{useCase.title}</h3>
                  <p className="text-sm text-white/70 leading-relaxed">{useCase.body}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
