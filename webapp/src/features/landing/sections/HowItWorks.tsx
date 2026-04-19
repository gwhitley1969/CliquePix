import { Calendar, Camera, Download } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

const STEPS: { index: string; title: string; body: string; icon: LucideIcon }[] = [
  {
    index: '01',
    title: 'Start an Event',
    body: 'Name the moment, pick a duration — 24 hours, 3 days, or a week. Invite your Clique or create one inline.',
    icon: Calendar,
  },
  {
    index: '02',
    title: 'Share in real time',
    body: 'Take a photo, record a video, or upload from your gallery. Everyone in the Clique sees it instantly.',
    icon: Camera,
  },
  {
    index: '03',
    title: 'Save what matters',
    body: 'React, download the shots you love to your device. Everything else auto-deletes when the event ends.',
    icon: Download,
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
