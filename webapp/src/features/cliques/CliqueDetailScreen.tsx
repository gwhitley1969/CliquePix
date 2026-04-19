import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useState } from 'react';
import { toast } from 'sonner';
import { ChevronLeft, LogOut, Share2, UserMinus } from 'lucide-react';
import {
  getClique,
  leaveClique,
  listMembers,
  removeMember,
} from '../../api/endpoints/cliques';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { Button } from '../../components/Button';
import { ConfirmDestructive } from '../../components/ConfirmDestructive';
import { InviteDialog } from './InviteDialog';

export function CliqueDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [inviteOpen, setInviteOpen] = useState(false);
  const [leaveConfirm, setLeaveConfirm] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<{ userId: string; name: string } | null>(
    null,
  );

  const clique = useQuery({ queryKey: ['clique', id], queryFn: () => getClique(id!), enabled: !!id });
  const members = useQuery({
    queryKey: ['clique', id, 'members'],
    queryFn: () => listMembers(id!),
    enabled: !!id,
  });

  const leaveMut = useMutation({
    mutationFn: () => leaveClique(id!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['cliques'] });
      toast.success('You left the clique');
      navigate('/cliques');
    },
    onError: () => toast.error('Failed to leave clique'),
  });

  const removeMut = useMutation({
    mutationFn: (userId: string) => removeMember(id!, userId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['clique', id, 'members'] });
      toast.success('Member removed');
      setRemoveTarget(null);
    },
    onError: () => toast.error('Failed to remove member'),
  });

  if (clique.isLoading) return <LoadingSpinner />;
  if (!clique.data) return <div className="p-6 text-white/60">Clique not found.</div>;

  const isOwner = clique.data.role === 'owner';

  return (
    <div className="max-w-3xl mx-auto px-4 py-6">
      <Link
        to="/cliques"
        className="inline-flex items-center gap-1 text-sm text-white/60 hover:text-white mb-4"
      >
        <ChevronLeft size={16} /> Back
      </Link>

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">{clique.data.name}</h1>
        <div className="flex gap-2">
          <Button onClick={() => setInviteOpen(true)}>
            <Share2 size={16} className="mr-1" /> Invite
          </Button>
          <Button variant="ghost" onClick={() => setLeaveConfirm(true)}>
            <LogOut size={16} className="mr-1" /> Leave
          </Button>
        </div>
      </div>

      <h2 className="text-sm uppercase tracking-wide text-white/50 mb-2">Members</h2>
      {members.isLoading ? (
        <LoadingSpinner />
      ) : (
        <ul className="space-y-1">
          {members.data?.map((m) => (
            <li
              key={m.userId}
              className="flex items-center justify-between p-3 rounded bg-dark-card border border-white/10"
            >
              <div>
                <div className="text-white">{m.displayName}</div>
                <div className="text-xs text-white/50">
                  {m.role === 'owner' ? 'Owner' : 'Member'}
                </div>
              </div>
              {isOwner && m.role !== 'owner' && (
                <button
                  onClick={() => setRemoveTarget({ userId: m.userId, name: m.displayName })}
                  className="text-white/50 hover:text-error"
                  aria-label="Remove member"
                >
                  <UserMinus size={16} />
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      <InviteDialog
        open={inviteOpen}
        onOpenChange={setInviteOpen}
        cliqueId={clique.data.id}
        cliqueName={clique.data.name}
      />

      <ConfirmDestructive
        open={leaveConfirm}
        onOpenChange={setLeaveConfirm}
        title={`Leave ${clique.data.name}?`}
        message="You'll stop receiving notifications for this clique's events. You can rejoin if you get a new invite."
        confirmLabel="Leave"
        onConfirm={() => leaveMut.mutate()}
        loading={leaveMut.isPending}
      />

      <ConfirmDestructive
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title={`Remove ${removeTarget?.name ?? ''}?`}
        message="They'll lose access to this clique's events immediately."
        confirmLabel="Remove"
        onConfirm={() => {
          if (removeTarget) removeMut.mutate(removeTarget.userId);
        }}
        loading={removeMut.isPending}
      />
    </div>
  );
}
