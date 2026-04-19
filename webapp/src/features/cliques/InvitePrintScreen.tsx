import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { Printer } from 'lucide-react';
import { getClique, getInvite } from '../../api/endpoints/cliques';
import { Button } from '../../components/Button';
import { trackEvent } from '../../lib/ai';

// Brand gradient as an inline style so it prints without the user having to
// toggle "Background graphics" in their browser's print settings. Mirrors
// --gradient-primary in styles/tokens.css.
const GRADIENT = 'linear-gradient(135deg, #00C2D1 0%, #2563EB 50%, #7C3AED 100%)';
const PRINT_COLORS: React.CSSProperties = {
  WebkitPrintColorAdjust: 'exact',
  printColorAdjust: 'exact',
};

export function InvitePrintScreen() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const clique = useQuery({
    queryKey: ['clique', id],
    queryFn: () => getClique(id!),
    enabled: !!id,
  });
  const invite = useQuery({
    queryKey: ['clique', id, 'invite'],
    queryFn: () => getInvite(id!),
    enabled: !!id,
  });

  const ready = clique.data && invite.data;

  useEffect(() => {
    if (ready) {
      trackEvent('web_qr_printed', { clique_id: id });
      const t = setTimeout(() => window.print(), 400);
      return () => clearTimeout(t);
    }
  }, [ready, id]);

  if (!clique.data || !invite.data) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white text-black">
        Loading…
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-100 print:bg-white flex flex-col items-center justify-center py-10 px-4">
      {/* Chrome — hidden on print */}
      <div className="no-print mb-6 flex gap-2">
        <Button variant="ghost" onClick={() => navigate(`/cliques/${id}`)}>
          Back
        </Button>
        <Button onClick={() => window.print()}>
          <Printer size={16} className="mr-1" /> Print
        </Button>
      </div>

      {/* Invite card */}
      <div
        className="bg-white w-full max-w-[576px] rounded-2xl overflow-hidden shadow-2xl print:shadow-none print:rounded-none print:border print:border-gray-200"
        style={PRINT_COLORS}
      >
        {/* Gradient header: logo + wordmark */}
        <div
          className="px-8 pt-8 pb-6 text-center"
          style={{ background: GRADIENT, ...PRINT_COLORS }}
        >
          <img
            src="/assets/icon.png"
            alt="Clique Pix"
            className="w-16 h-16 mx-auto mb-3 rounded-xl shadow-md"
            style={PRINT_COLORS}
          />
          <div className="text-3xl font-bold text-white tracking-tight leading-none">
            Clique Pix
          </div>
          <div className="text-[11px] text-white/90 mt-2 uppercase tracking-[0.2em] font-medium">
            Private Event Photo Sharing
          </div>
        </div>

        {/* Hero — clique name */}
        <div className="px-8 pt-8 pb-4 text-center">
          <div className="text-xs uppercase tracking-[0.18em] text-gray-500 font-semibold">
            You're invited to join
          </div>
          <h1 className="text-3xl font-bold mt-2 text-gray-900 leading-tight break-words">
            {clique.data.name}
          </h1>
        </div>

        {/* QR code */}
        <div className="px-8 py-4 flex justify-center">
          <div className="bg-white p-4 border-2 border-gray-100 rounded-xl">
            <QRCodeSVG
              value={invite.data.inviteUrl}
              size={260}
              level="M"
              fgColor="#000000"
              bgColor="#FFFFFF"
            />
          </div>
        </div>

        {/* Instructions + code */}
        <div className="px-8 pt-2 pb-8 text-center">
          <div className="text-sm text-gray-700 font-medium">
            Scan with your phone camera
          </div>
          <div className="mt-5 text-[11px] uppercase tracking-[0.18em] text-gray-400 font-semibold">
            or enter code at clique-pix.com/invite
          </div>
          <div className="inline-block mt-2 px-5 py-3 rounded-lg bg-gray-50 border border-gray-200 font-mono text-2xl tracking-[0.25em] text-gray-900 font-bold">
            {invite.data.inviteCode}
          </div>
        </div>

        {/* Gradient footer band */}
        <div
          className="px-8 py-3 text-center"
          style={{ background: GRADIENT, ...PRINT_COLORS }}
        >
          <div className="text-xs text-white tracking-[0.14em] font-semibold">
            clique-pix.com
          </div>
        </div>
      </div>

      {/* Back link — hidden on print */}
      <div className="no-print mt-6">
        <Link
          to={`/cliques/${id}`}
          className="text-sm text-gray-600 hover:text-gray-900 underline"
        >
          Back to Clique
        </Link>
      </div>
    </div>
  );
}
