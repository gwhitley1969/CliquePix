import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useState } from 'react';
import { Plus, Users } from 'lucide-react';
import { toast } from 'sonner';
import { createClique, listCliques } from '../../api/endpoints/cliques';
import { Button } from '../../components/Button';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { EmptyState } from '../../components/EmptyState';
import { ErrorState } from '../../components/ErrorState';
import { Modal } from '../../components/Modal';

export function CliquesListScreen() {
  const qc = useQueryClient();
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState('');
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['cliques'],
    queryFn: listCliques,
  });

  const mutation = useMutation({
    mutationFn: () => createClique(name.trim()),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['cliques'] });
      toast.success('Clique created');
      setName('');
      setCreateOpen(false);
    },
    onError: () => toast.error('Failed to create clique'),
  });

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Cliques</h1>
        <Button onClick={() => setCreateOpen(true)}>
          <Plus size={16} className="mr-1" /> New Clique
        </Button>
      </div>

      {isLoading ? (
        <LoadingSpinner />
      ) : isError ? (
        <ErrorState
          title="Couldn't load Cliques"
          subtitle="We couldn't reach the server. Check your connection and try again."
          onRetry={() => refetch()}
        />
      ) : !data || data.length === 0 ? (
        <EmptyState
          icon={Users}
          title="No Cliques yet"
          subtitle="A Clique is a reusable group of people you share Events with."
          action={<Button onClick={() => setCreateOpen(true)}>Create your first Clique</Button>}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {data.map((c) => (
            <Link
              key={c.id}
              to={`/cliques/${c.id}`}
              className="block p-4 rounded-lg bg-dark-card border border-white/10 hover:border-aqua/50 transition-colors"
            >
              <div className="text-lg font-semibold">{c.name}</div>
              <div className="text-sm text-white/60 mt-1">
                {c.memberCount ?? 0} member{(c.memberCount ?? 0) === 1 ? '' : 's'}
              </div>
            </Link>
          ))}
        </div>
      )}

      <Modal open={createOpen} onOpenChange={setCreateOpen} title="New Clique">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (!name.trim()) return;
            mutation.mutate();
          }}
          className="space-y-4"
        >
          <div>
            <label className="block text-sm mb-1 text-white/80">Name</label>
            <input
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Girls Night Out"
              className="w-full rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={() => setCreateOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? 'Creating…' : 'Create'}
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
