import { Link } from 'react-router-dom';
import { useIsAuthenticated } from '@azure/msal-react';
import { ArrowRight } from 'lucide-react';
import { BetaChip } from '../components/BetaChip';
import { PhoneMockup } from '../components/PhoneMockup';
import { DemoMediaCard } from '../components/DemoMediaCard';
import { AppStoreBadge } from '../components/AppStoreBadge';
import { PlayStoreBadge } from '../components/PlayStoreBadge';

export function Hero() {
  const isAuthenticated = useIsAuthenticated();
  const primaryHref = isAuthenticated ? '/events' : '/login';
  const primaryLabel = isAuthenticated ? 'Open my events' : 'Get Started';

  return (
    <section className="relative overflow-hidden">
      {/* Animated gradient spotlights */}
      <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
        <div
          className="absolute top-[10%] left-[-10%] w-[50rem] h-[50rem] rounded-full opacity-30 blur-3xl animate-[landing-drift-a_28s_ease-in-out_infinite]"
          style={{
            background: 'radial-gradient(circle, rgba(0,194,209,0.6), transparent 60%)',
          }}
        />
        <div
          className="absolute top-[30%] right-[-10%] w-[40rem] h-[40rem] rounded-full opacity-25 blur-3xl animate-[landing-drift-b_34s_ease-in-out_infinite]"
          style={{
            background: 'radial-gradient(circle, rgba(124,58,237,0.55), transparent 60%)',
          }}
        />
        <div
          className="absolute bottom-[-10%] left-[30%] w-[45rem] h-[45rem] rounded-full opacity-20 blur-3xl animate-[landing-drift-c_40s_ease-in-out_infinite]"
          style={{
            background: 'radial-gradient(circle, rgba(37,99,235,0.5), transparent 60%)',
          }}
        />
      </div>

      <div className="relative max-w-6xl mx-auto px-4 md:px-8 pt-10 md:pt-16 pb-16 md:pb-24 grid md:grid-cols-2 gap-10 md:gap-16 items-center">
        <div>
          <div className="mb-5">
            <BetaChip />
            <span className="hidden sm:inline ml-2 text-[10px] uppercase tracking-[0.18em] text-white/40">
              · iOS · Android · Web
            </span>
          </div>

          <h1 className="text-[2.5rem] sm:text-5xl md:text-6xl font-bold tracking-tight leading-[1.05] text-white">
            Your moments.
            <br />
            Your people.
            <br />
            <span className="bg-gradient-primary bg-clip-text text-transparent">
              No strangers.
            </span>
          </h1>

          <p className="mt-6 max-w-lg text-base md:text-lg text-white/70 leading-relaxed">
            Private photo and video sharing for the people who were actually there.
            Weddings, trips, parties, family — share in real time with just your
            group, then save what matters and let the rest disappear.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link
              to={primaryHref}
              className="inline-flex items-center gap-2 rounded-lg px-6 py-3 text-base font-semibold text-white bg-gradient-primary hover:opacity-95 transition-opacity focus:outline-none focus:ring-2 focus:ring-aqua/50 shadow-lg shadow-deepBlue/20"
            >
              {primaryLabel} <ArrowRight size={18} />
            </Link>
            <AppStoreBadge />
            <PlayStoreBadge />
          </div>
          <p className="mt-3 text-xs text-white/40">
            App Store + Google Play links coming soon — sign in from the web today.
          </p>
        </div>

        <div className="relative">
          <PhoneMockup>
            <div className="text-center mb-3">
              <div className="text-[9px] uppercase tracking-[0.22em] text-aqua">Event</div>
              <div className="text-base font-bold text-white">Friday Night — Downtown</div>
              <div className="text-[10px] text-white/50">6h remaining · 4 people</div>
            </div>
            <DemoMediaCard />
          </PhoneMockup>
        </div>
      </div>
    </section>
  );
}
