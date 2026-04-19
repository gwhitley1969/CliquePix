import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { AxiosError } from 'axios';
import { ChevronLeft, Send } from 'lucide-react';
import { toast } from 'sonner';
import { useMsal } from '@azure/msal-react';
import {
  getThread,
  listThreadMessages,
  markThreadRead,
  sendMessage,
} from '../../api/endpoints/messages';
import { LoadingSpinner } from '../../components/LoadingSpinner';
import { formatRelative } from '../../lib/formatDate';

export function ThreadScreen() {
  const { id: eventId, threadId } = useParams<{ id: string; threadId: string }>();
  const qc = useQueryClient();
  const { accounts } = useMsal();
  const myUserId = accounts[0]?.localAccountId;
  const [draft, setDraft] = useState('');
  const bottomRef = useRef<HTMLDivElement>(null);

  const thread = useQuery({
    queryKey: ['thread', threadId],
    queryFn: () => getThread(threadId!),
    enabled: !!threadId,
  });
  const messages = useQuery({
    queryKey: ['thread', threadId, 'messages'],
    queryFn: () => listThreadMessages(threadId!),
    enabled: !!threadId,
  });

  useEffect(() => {
    if (threadId) markThreadRead(threadId).catch(console.error);
  }, [threadId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.data?.length]);

  const sendMut = useMutation({
    mutationFn: (body: string) => sendMessage(threadId!, body),
    onSuccess: () => {
      setDraft('');
      qc.invalidateQueries({ queryKey: ['thread', threadId, 'messages'] });
    },
    onError: (err) => {
      const status = err instanceof AxiosError ? err.response?.status : undefined;
      if (status === 429) {
        toast.error('Slow down — max 10 messages per minute.');
      } else {
        toast.error('Failed to send message');
      }
    },
  });

  if (thread.isLoading) return <LoadingSpinner />;

  const readOnly = thread.data?.readOnly;

  return (
    <div className="h-full flex flex-col max-w-2xl mx-auto w-full">
      <header className="px-4 py-3 border-b border-white/10 flex items-center gap-3">
        <Link to={`/events/${eventId}/messages`} className="text-white/60 hover:text-white">
          <ChevronLeft size={20} />
        </Link>
        <div className="font-medium">{thread.data?.otherUser.displayName ?? ''}</div>
      </header>
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3">
        {messages.data?.map((m) => {
          const mine = m.senderUserId === myUserId;
          return (
            <div
              key={m.id}
              className={`max-w-[70%] ${mine ? 'ml-auto' : ''}`}
            >
              <div
                className={`rounded-lg px-3 py-2 text-sm ${
                  mine ? 'bg-gradient-primary text-white' : 'bg-dark-card text-white/90'
                }`}
              >
                {m.body}
              </div>
              <div
                className={`text-[10px] text-white/40 mt-1 ${mine ? 'text-right' : ''}`}
              >
                {formatRelative(m.createdAt)}
              </div>
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>
      {readOnly ? (
        <div className="p-4 text-center text-sm text-white/50 border-t border-white/10">
          This event has expired — messages are read-only.
        </div>
      ) : (
        <form
          className="p-3 border-t border-white/10 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (!draft.trim() || sendMut.isPending) return;
            sendMut.mutate(draft.trim());
          }}
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Type a message"
            className="flex-1 rounded px-3 py-2 bg-dark-bg border border-white/10 text-white focus:outline-none focus:border-aqua"
          />
          <button
            type="submit"
            disabled={!draft.trim() || sendMut.isPending}
            className="inline-flex items-center justify-center rounded bg-gradient-primary px-3 py-2 text-white disabled:opacity-50"
          >
            <Send size={16} />
          </button>
        </form>
      )}
    </div>
  );
}
