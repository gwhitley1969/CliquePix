import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { Copy, Printer, Share2 } from 'lucide-react';
import { toast } from 'sonner';
import { Modal } from '../../components/Modal';
import { Button } from '../../components/Button';
import { getInvite } from '../../api/endpoints/cliques';

export function InviteDialog({
  open,
  onOpenChange,
  cliqueId,
  cliqueName,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  cliqueId: string;
  cliqueName: string;
}) {
  const navigate = useNavigate();
  const invite = useQuery({
    queryKey: ['clique', cliqueId, 'invite'],
    queryFn: () => getInvite(cliqueId),
    enabled: open,
  });

  const url = invite.data?.inviteUrl ?? '';
  const code = invite.data?.inviteCode ?? '';

  const onCopy = async () => {
    if (!url) return;
    await navigator.clipboard.writeText(url);
    toast.success('Invite link copied');
  };

  const onShare = async () => {
    if (!url) return;
    if (navigator.share) {
      try {
        await navigator.share({
          title: `Join ${cliqueName} on Clique Pix`,
          text: `Join ${cliqueName} on Clique Pix`,
          url,
        });
      } catch {
        /* user cancelled */
      }
    } else {
      onCopy();
    }
  };

  return (
    <Modal open={open} onOpenChange={onOpenChange} title={`Invite to ${cliqueName}`}>
      <div className="flex flex-col items-center gap-4">
        <div className="bg-white p-4 rounded-lg">
          {url ? (
            <QRCodeSVG value={url} size={200} level="M" />
          ) : (
            <div className="w-[200px] h-[200px] flex items-center justify-center text-black/50 text-sm">
              Generating…
            </div>
          )}
        </div>
        <div className="w-full">
          <label className="text-xs text-white/50 uppercase tracking-wide">Invite code</label>
          <div className="mt-1 p-2 rounded bg-dark-bg border border-white/10 font-mono text-center text-lg">
            {code || '…'}
          </div>
        </div>
        <div className="w-full flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onCopy} disabled={!url}>
            <Copy size={16} className="mr-1" /> Copy link
          </Button>
          <Button variant="secondary" className="flex-1" onClick={onShare} disabled={!url}>
            <Share2 size={16} className="mr-1" /> Share
          </Button>
        </div>
        <Button
          className="w-full"
          onClick={() => navigate(`/cliques/${cliqueId}/invite/print`)}
          disabled={!url}
        >
          <Printer size={16} className="mr-1" /> Print QR code
        </Button>
      </div>
    </Modal>
  );
}
