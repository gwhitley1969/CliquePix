import * as Dialog from '@radix-ui/react-dialog';
import * as Tabs from '@radix-ui/react-tabs';
import { useQuery } from '@tanstack/react-query';
import { X } from 'lucide-react';
import { useEffect } from 'react';
import { Avatar } from '../../components/Avatar';
import { trackEvent } from '../../lib/ai';
import type { ReactionType, ReactorEntry, ReactorList } from '../../models';

const REACTION_ORDER: ReactionType[] = ['heart', 'laugh', 'fire', 'wow'];
const EMOJI: Record<ReactionType, string> = {
  heart: '❤️',
  laugh: '😂',
  fire: '🔥',
  wow: '😮',
};

/**
 * "Who reacted?" Radix Dialog with per-reaction-type tabs. Refetches on
 * every open via react-query (`enabled: open`). One row per reaction —
 * a user who left both heart AND fire shows up twice on the All tab,
 * once on each per-type tab. Empty types are skipped.
 *
 * Mirror of the mobile ReactorListSheet; same data shape, same tab
 * order, same telemetry semantics (server-side `reactor_list_fetched`
 * fires on every GET).
 */
export function ReactorListDialog({
  open,
  onOpenChange,
  mediaId,
  mediaType,
  initialFilter,
  fetchReactors,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mediaId: string;
  mediaType: 'photo' | 'video';
  initialFilter?: ReactionType | null;
  fetchReactors: () => Promise<ReactorList>;
}) {
  const query = useQuery({
    queryKey: ['reactors', mediaType, mediaId],
    queryFn: fetchReactors,
    enabled: open,
    staleTime: 0, // refetch on every dialog open
    gcTime: 0,
  });

  // One-shot telemetry per successful dialog load. useEffect ensures we
  // fire once per fetch result, not on every render.
  useEffect(() => {
    if (open && query.data) {
      trackEvent('web_reactor_list_viewed', {
        mediaId,
        mediaType,
        reactionFilter: initialFilter ?? 'all',
        totalReactions: query.data.totalReactions,
      });
    }
  }, [open, query.data, mediaId, mediaType, initialFilter]);

  const data = query.data;
  const tabs = buildTabs(data);
  const initialTab = initialFilter && tabs.some((t) => t.value === initialFilter)
    ? initialFilter
    : 'all';

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60 z-40" />
        <Dialog.Content className="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[92vw] max-w-md bg-dark-card rounded-lg border border-white/10 focus:outline-none max-h-[85vh] overflow-hidden flex flex-col z-50">
          <header className="flex items-center justify-between px-5 py-4 border-b border-white/10">
            <Dialog.Title className="text-lg font-semibold text-white">
              Reactions
            </Dialog.Title>
            <Dialog.Close
              className="text-white/60 hover:text-white focus:outline-none focus:ring-2 focus:ring-aqua/50 rounded p-1"
              aria-label="Close"
            >
              <X size={20} />
            </Dialog.Close>
          </header>

          {query.isLoading ? (
            <SkeletonList />
          ) : query.isError || !data ? (
            <ErrorState onRetry={() => query.refetch()} />
          ) : (
            <Tabs.Root
              defaultValue={initialTab}
              className="flex flex-col flex-1 overflow-hidden"
            >
              <Tabs.List className="flex gap-1 px-3 py-2 border-b border-white/10 overflow-x-auto">
                {tabs.map((tab) => (
                  <Tabs.Trigger
                    key={tab.value}
                    value={tab.value}
                    className="px-3 py-1.5 rounded text-sm font-medium text-white/55 data-[state=active]:text-white data-[state=active]:bg-white/5 hover:text-white/80 focus:outline-none focus:ring-2 focus:ring-aqua/50 whitespace-nowrap"
                  >
                    {tab.label}
                  </Tabs.Trigger>
                ))}
              </Tabs.List>
              {tabs.map((tab) => {
                const reactors =
                  tab.value === 'all'
                    ? data.reactors
                    : data.reactors.filter((r) => r.reactionType === tab.value);
                return (
                  <Tabs.Content
                    key={tab.value}
                    value={tab.value}
                    className="flex-1 overflow-y-auto px-2 py-2 focus:outline-none"
                  >
                    {reactors.length === 0 ? (
                      <EmptyState />
                    ) : (
                      <ul className="flex flex-col">
                        {reactors.map((r) => (
                          <ReactorRow key={r.id} reactor={r} />
                        ))}
                      </ul>
                    )}
                  </Tabs.Content>
                );
              })}
            </Tabs.Root>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function ReactorRow({ reactor }: { reactor: ReactorEntry }) {
  const emoji = EMOJI[reactor.reactionType];
  return (
    <li className="flex items-center gap-3 px-3 py-2.5 hover:bg-white/5 rounded">
      <Avatar
        name={reactor.displayName}
        imageUrl={reactor.avatarUrl}
        thumbUrl={reactor.avatarThumbUrl}
        framePreset={reactor.avatarFramePreset}
        cacheBuster={
          reactor.avatarUpdatedAt
            ? `${reactor.userId}_${new Date(reactor.avatarUpdatedAt).getTime()}`
            : undefined
        }
        size={40}
      />
      <span className="flex-1 truncate text-white text-base font-medium">
        {reactor.displayName}
      </span>
      <span className="text-2xl leading-none">{emoji}</span>
    </li>
  );
}

function SkeletonList() {
  return (
    <ul className="px-5 py-3">
      {[0, 1, 2].map((i) => (
        <li key={i} className="flex items-center gap-3 py-2.5">
          <div className="w-10 h-10 rounded-full bg-white/5" />
          <div className="h-3.5 w-32 bg-white/5 rounded" />
        </li>
      ))}
    </ul>
  );
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center py-10 px-6 text-center">
      <p className="text-white/70 text-sm mb-4">Couldn't load reactions.</p>
      <button
        type="button"
        onClick={onRetry}
        className="text-aqua text-sm font-medium hover:underline focus:outline-none focus:ring-2 focus:ring-aqua/50 rounded px-2 py-1"
      >
        Retry
      </button>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex items-center justify-center py-10 px-6">
      <p className="text-white/55 text-sm">No one's reacted with this yet.</p>
    </div>
  );
}

type TabSpec = { value: 'all' | ReactionType; label: string };

function buildTabs(data: ReactorList | undefined): TabSpec[] {
  if (!data) return [{ value: 'all', label: 'All' }];
  const tabs: TabSpec[] = [{ value: 'all', label: `All ${data.totalReactions}` }];
  for (const t of REACTION_ORDER) {
    const count = data.byType[t] ?? 0;
    if (count > 0) tabs.push({ value: t, label: `${EMOJI[t]} ${count}` });
  }
  return tabs;
}

