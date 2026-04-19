import { Link } from 'react-router-dom';
import { useIsAuthenticated } from '@azure/msal-react';
import { ArrowRight } from 'lucide-react';
import { BetaChip } from '../components/BetaChip';

export function LandingNav() {
  const isAuthenticated = useIsAuthenticated();

  return (
    <header className="sticky top-0 z-40 backdrop-blur-md bg-dark-bg/70 border-b border-white/5">
      <div className="max-w-6xl mx-auto px-4 md:px-8 h-14 flex items-center justify-between">
        <Link to="/" className="flex items-center gap-3 group">
          <img
            src="/assets/icon.png"
            alt=""
            className="w-8 h-8 rounded-lg shadow-md"
          />
          <span className="text-lg font-bold bg-gradient-primary bg-clip-text text-transparent">
            Clique Pix
          </span>
          <BetaChip className="hidden sm:inline-flex" />
        </Link>

        {isAuthenticated ? (
          <Link
            to="/events"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-white/80 hover:text-white transition-colors"
          >
            My Events <ArrowRight size={16} />
          </Link>
        ) : (
          <Link
            to="/login"
            className="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium text-white bg-white/10 hover:bg-white/15 transition-colors"
          >
            Sign in
          </Link>
        )}
      </div>
    </header>
  );
}
