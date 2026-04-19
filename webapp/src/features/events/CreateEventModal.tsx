import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Modal } from '../../components/Modal';
import { Button } from '../../components/Button';
import { createEvent } from '../../api/endpoints/events';
import { createClique, listCliques } from '../../api/endpoints/cliques';

const RETENTION_OPTIONS = [
  { hours: 24 as const, label: '24 hours' },
  { hours: 72 as const, label: '3 days' },
  { hours: 168 as const, label: '7 days' },
];

export function CreateEventModal({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const qc = useQueryClient();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [retentionHours, setRetentionHours] = useState<24 | 72 | 168>(168);
  const [cliqueId, setCliqueId] = useState('');
  const [newCliqueName, setNewCliqueName] = useState('');
  const [createNew, setCreateNew] = useState(false);

  const cliques = useQuery({ queryKey: ['cliques'], queryFn: listCliques, enabled: open });

  const mutation = useMutation({
    mutationFn: async () => {
      let targetCliqueId = cliqueId;
      if (createNew) {
        if (!newCliqueName.trim()) throw new Error('Clique name is required');
        const created = await createClique(newCliqueName.trim());
        targetCliqueId = created.id;
        qc.invalidateQueries({ queryKey: ['cliques'] });
      }
      if (!targetCliqueId) throw new Error('Pick or create a Clique');
      return createEvent({
        cliqueId: targetCliqueId,
        name: name.trim(),
        description: description.trim() || undefined,
        retentionHours,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['events'] });
      toast.success('Event created');
      reset();
      onOpenChange(false);
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : 'Failed to create event');
    },
  });

  const reset = () => {
    setName('');
    setDescription('');
    setRetentionHours(168);
    setCliqueId('');
    setNewCliqueName('');
    setCreateNew(false);
  };

  return (
    <Modal open={open} onOpenChange={onOpenChange} title="New Event">
      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          mutation.mutate();
        }}
      >
        <div>
          <label className="block text-sm mb-1 text-white/80">Name</label>
          <input
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Friday Night Downtown"
            className="w-full rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
          />
        </div>
        <div>
          <label className="block text-sm mb-1 text-white/80">Description (optional)</label>
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
          />
        </div>
        <div>
          <label className="block text-sm mb-2 text-white/80">Duration</label>
          <div className="flex gap-2">
            {RETENTION_OPTIONS.map((opt) => (
              <button
                key={opt.hours}
                type="button"
                onClick={() => setRetentionHours(opt.hours)}
                className={`flex-1 py-2 rounded text-sm border transition-colors ${
                  retentionHours === opt.hours
                    ? 'bg-gradient-primary border-transparent text-white'
                    : 'bg-dark-bg border-white/10 text-white/70 hover:border-white/30'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>
        <div>
          <label className="block text-sm mb-1 text-white/80">Clique</label>
          {!createNew ? (
            <>
              <select
                value={cliqueId}
                onChange={(e) => setCliqueId(e.target.value)}
                className="w-full rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
              >
                <option value="">Pick a Clique…</option>
                {cliques.data?.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
              <button
                type="button"
                onClick={() => setCreateNew(true)}
                className="mt-2 text-xs text-aqua hover:underline"
              >
                + Create a new Clique
              </button>
            </>
          ) : (
            <>
              <input
                value={newCliqueName}
                onChange={(e) => setNewCliqueName(e.target.value)}
                placeholder="New clique name"
                className="w-full rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
              />
              <button
                type="button"
                onClick={() => setCreateNew(false)}
                className="mt-2 text-xs text-white/60 hover:underline"
              >
                Pick an existing Clique instead
              </button>
            </>
          )}
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button
            type="button"
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={mutation.isPending}
          >
            Cancel
          </Button>
          <Button type="submit" disabled={mutation.isPending}>
            {mutation.isPending ? 'Creating…' : 'Create Event'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
