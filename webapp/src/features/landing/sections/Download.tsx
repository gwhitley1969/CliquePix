import { Link } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { ArrowRight } from 'lucide-react';
import { AppStoreBadge } from '../components/AppStoreBadge';
import { PlayStoreBadge } from '../components/PlayStoreBadge';
import { BetaChip } from '../components/BetaChip';
import { useRevealOnScroll } from '../hooks/useRevealOnScroll';

export function Download() {
  const { ref, revealed } = useRevealOnScroll<HTMLDivElement>();
  return (
    <section
      className="relative border-y border-white/10"
      style={{
        background:
          'linear-gradient(135deg, rgba(0,194,209,0.18) 0%, rgba(37,99,235,0.18) 50%, rgba(124,58,237,0.18) 100%)',
      }}
    >
      <div className="max-w-6xl mx-auto px-4 md:px-8 py-16 md:py-20">
        <div
          ref={ref}
          className={`grid md:grid-cols-[1fr_auto] gap-10 md:gap-16 items-center transition-all duration-700 ${
            revealed ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'
          }`}
        >
          <div>
            <h2 className="text-3xl md:text-4xl font-bold text-white">Get Clique Pix</h2>
            <p className="mt-3 text-white/70 max-w-lg">
              Install the app on your phone, or sign in from any browser. It's the same Cliques,
              same Events, same photos everywhere you go.
            </p>

            <div className="mt-7 flex flex-wrap items-center gap-3">
              <AppStoreBadge />
              <PlayStoreBadge />
            </div>
            <div className="mt-4 flex items-center gap-2">
              <BetaChip />
              <span className="text-xs text-white/50">Store listings coming soon</span>
            </div>

            <div className="mt-8">
              <Link
                to="/login"
                className="inline-flex items-center gap-1.5 text-sm font-medium text-white hover:text-aqua transition-colors"
              >
                Or sign in from the web <ArrowRight size={16} />
              </Link>
            </div>
          </div>

          <div className="flex flex-col items-center">
            <div className="bg-white rounded-xl p-4">
              <QRCodeSVG value="https://clique-pix.com" size={168} level="M" />
            </div>
            <div className="mt-3 text-xs uppercase tracking-wider text-white/60 text-center">
              Scan to open on your phone
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
