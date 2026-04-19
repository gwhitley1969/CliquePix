import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { getClique, getInvite } from '../../api/endpoints/cliques';
import { Button } from '../../components/Button';
import { trackEvent } from '../../lib/ai';

export function InvitePrintScreen() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const clique = useQuery({ queryKey: ['clique', id], queryFn: () => getClique(id!), enabled: !!id });
  const invite = useQuery({
    queryKey: ['clique', id, 'invite'],
    queryFn: () => getInvite(id!),
    enabled: !!id,
  });

  const ready = clique.data && invite.data;

  useEffect(() => {
    if (ready) {
      trackEvent('web_qr_printed', { clique_id: id });
      const t = setTimeout(() => window.print(), 300);
      return () => clearTimeout(t);
    }
  }, [ready, id]);

  if (!clique.data || !invite.data) {
    return <div className="min-h-screen flex items-center justify-center">Loading…</div>;
  }

  return (
    <div className="min-h-screen bg-white text-black flex flex-col items-center justify-center py-12 px-6 print:bg-white print:text-black">
      <div className="no-print mb-6 flex gap-2">
        <Button variant="ghost" onClick={() => navigate(`/cliques/${id}`)}>
          Back
        </Button>
        <Button onClick={() => window.print()}>Print</Button>
      </div>
      <div className="max-w-md w-full text-center">
        <h1 className="text-2xl font-bold mb-2">{clique.data.name}</h1>
        <p className="text-sm text-gray-600 mb-8">Scan to join on Clique Pix</p>
        <div className="inline-block p-6 border border-gray-300 rounded-lg">
          <QRCodeSVG value={invite.data.invite_url} size={280} level="M" />
        </div>
        <p className="mt-6 text-sm text-gray-600">Or enter this code at clique-pix.com/invite</p>
        <p className="mt-2 font-mono text-2xl tracking-widest">{invite.data.invite_code}</p>
        <p className="mt-8 text-xs text-gray-400">
          Clique Pix — private, event-based photo sharing
        </p>
      </div>
      <div className="no-print mt-6">
        <Link to={`/cliques/${id}`} className="text-sm text-gray-500 hover:text-black underline">
          Back to Clique
        </Link>
      </div>
    </div>
  );
}
