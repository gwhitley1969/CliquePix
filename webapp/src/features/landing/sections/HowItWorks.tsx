import { Calendar, Camera, Users } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

// Marketing narrative splits "Event creation" and "Clique setup" into two
// distinct steps so the "your people" message from the hero has its own beat.
// The real app keeps those in a single flow (Clique picker appears inside
// Event creation) — the landing page just decomposes them for clarity.
const STEPS: { index: string; title: string; body: string; icon: LucideIcon }[] = [
  {
    index: '01',
    title: 'Start an Event',
    body: 'Name the moment, pick a duration — 24 hours, 3 days, or a week.',
    icon: Calendar,
  },
  {
    index: '02',
    title: 'Create or invite your Clique',
    body: 'Spin up a new group, or invite people from a Clique you already use. Share a link, QR code, or SMS — they join in a tap.',
    icon: Users,
  },
  {
    index: '03',
    title: 'Share, react, save what matters',
    body: 'Everyone uploads in real time. React, save the shots you love — the rest auto-deletes when the event ends.',
    icon: Camera,
  },
];

export function HowItWorks() {
  const { ref, revealed } = useRevealOnScroll<HTMLDivElement>();
  return (
    <section className="bg-dark-surface border-y border-white/5">
      <div className="max-w-6xl mx-auto px-4 md:px-8 py-16 md:py-20">
        <div
          ref={ref}
          className={`transition-all duration-700 ${
            revealed ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
          }`}
        >
          <div className="max-w-2xl mb-10 md:mb-12">
            <h2 className="text-3xl md:text-4xl font-bold text-white">How it works</h2>
            <p className="mt-3 text-white/60">
              Designed around the real moments you're already living. Three steps from "let's
              capture this" to "saved the good ones, forgot the rest."
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-5">
            {STEPS.map((step) => (
              <div
                key={step.index}
                className="relative rounded-xl bg-dark-card border border-white/10 p-6 overflow-hidden"
              >
                <div
                  className="absolute top-0 left-0 right-0 h-0.5 bg-gradient-primary"
                  aria-hidden="true"
                />
                <div className="flex items-start justify-between mb-4">
                  <span className="text-3xl font-bold bg-gradient-primary bg-clip-text text-transparent">
                    {step.index}
                  </span>
                  <step.icon size={22} className="text-aqua mt-1.5" />
                </div>
                <h3 className="text-xl font-semibold text-white mb-2">{step.title}</h3>
                <p className="text-sm text-white/60 leading-relaxed">{step.body}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
