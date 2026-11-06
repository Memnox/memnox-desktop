import type { MemoryItemView } from '@memnox/core/wire';
import { Check, GraduationCap, Pencil, X } from 'lucide-react';
import { useEffect, useState } from 'react';
import { confidenceLine, duplicateLine, kindWord, moreLine, oldestFirst, statusWord, TAINTED_LINE } from '../../../core/domain/memory-lines';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Evidence, memoryNote, OriginLine } from './MemoryPage';
import { EmptyState, ReadFailed, StatusWord } from '../widgets';

/**
 * What your agent read out of your sources, and what other agents suggested, waiting on you oldest first.
 * Nothing here counts until it is confirmed, and a rule confirmed here still waits for its signature.
 */
export function LearnPage({ parts }: { parts: SettingsParts }) {
  const { memory } = parts;
  useObserved(memory);
  useEffect(() => {
    void memory.refreshLearn();
    // Evidence names its source, and the sources say where a file sits.
    if (memory.sources === undefined) void memory.refreshSources();
  }, []);
  // A signature on the island settles a rule, so the queue is read again.
  useEffect(() => parts.host.onHomeStale?.(() => void memory.refreshLearn()), []);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const said = (id: string, note: string) => setNotes((now) => ({ ...now, [id]: note }));

  const queue = memory.learn;
  if (queue === undefined) return memory.unreadable.learn ? <ReadFailed what="the Learn queue" retry={() => void memory.refreshLearn()} /> : null;
  const items = oldestFirst(queue.items);
  // A card answered here leaves the queue, and its line stays so the person sees what the press did.
  const answered = Object.keys(notes).filter((id) => !items.some((item) => item.id === id));
  return (
    <div className="flex flex-col gap-3">
      {answered.map((id) => (
        <p key={id} role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {notes[id]}
        </p>
      ))}
      {items.length === 0 ? (
        <EmptyState
          icon={GraduationCap}
          title="Nothing to confirm"
          body="When your agent reads a memory source, or another agent suggests something through memnox_suggest, it waits here until you confirm, edit or reject it."
        />
      ) : (
        <>
          <p className="text-footnote text-muted">{`${items.length} waiting, oldest first. Nothing here reaches an agent as settled until you confirm it.`}</p>
          {items.map((item) => (
            <Suggestion key={item.id} parts={parts} item={item} note={notes[item.id]} said={(note) => said(item.id, note)} />
          ))}
          {moreLine(queue.more) !== undefined && <p className="text-footnote text-muted">{moreLine(queue.more)}</p>}
        </>
      )}
    </div>
  );
}

function Suggestion({ parts, item, note, said }: { parts: SettingsParts; item: MemoryItemView; note: string | undefined; said: (note: string) => void }) {
  const { memory, words } = parts;
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(item.statement);
  const busy = memory.busy === item.id;
  const confidence = confidenceLine(item.extractorConfidence);
  const save = () => {
    void memory.edit(item.id, draft).then((outcome) => {
      said(memoryNote(outcome));
      if (outcome.kind !== 'failed') setEditing(false);
    });
  };
  return (
    <article className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <header className="flex flex-wrap items-center gap-2.5">
        <span className="rounded-full border border-panel-edge px-2 py-0.5 text-micro font-medium text-muted">{kindWord(item.kind)}</span>
        <OriginLine item={item} className="flex-1 text-footnote text-muted" />
        {item.tainted && <StatusWord tone="attention">{TAINTED_LINE}</StatusWord>}
        {item.proposalId !== undefined && <StatusWord tone="attention">Waiting for your signature on the island</StatusWord>}
        {item.status === 'conflicting' && <StatusWord tone={statusWord(item.status).tone}>{statusWord(item.status).word}</StatusWord>}
      </header>
      {editing ? (
        <textarea
          className="min-h-20 w-full mx-field rounded-lg border border-field-edge bg-field px-3 py-2 text-body text-foreground outline-none focus:border-primary"
          value={draft}
          aria-label="The statement"
          onChange={(event) => setDraft(event.target.value)}
          autoFocus
        />
      ) : (
        <p className="whitespace-pre-wrap text-body text-foreground">{item.statement}</p>
      )}
      {item.rule !== undefined && (
        <p className="rounded-lg bg-hover px-3 py-2 text-footnote text-foreground">{`What it would govern: ${item.rule.sentence}`}</p>
      )}
      {item.duplicateOf !== undefined && <p className="whitespace-pre-wrap text-footnote text-muted">{duplicateLine(item.duplicateOf)}</p>}
      {confidence !== undefined && <p className="text-footnote text-muted">{confidence}</p>}
      <Evidence parts={parts} evidence={item.evidence} />
      <div className="flex flex-wrap items-center gap-2">
        {editing ? (
          <>
            <KitButton kind="primary" disabled={busy || draft.trim() === ''} onClick={save}>
              Save
            </KitButton>
            <KitButton
              onClick={() => {
                setDraft(item.statement);
                setEditing(false);
              }}
            >
              Cancel
            </KitButton>
          </>
        ) : (
          <>
            <KitButton kind="primary" icon={Check} disabled={busy || item.proposalId !== undefined} onClick={() => void memory.confirm(item.id, words.keyTitle).then((outcome) => said(memoryNote(outcome)))}>
              Confirm
            </KitButton>
            <KitButton icon={Pencil} disabled={busy} onClick={() => setEditing(true)}>
              Edit
            </KitButton>
            {/* Set apart from Confirm, so a rejection is never pressed by a slip. */}
            <span className="flex-1" />
            <KitButton icon={X} disabled={busy} onClick={() => void memory.reject(item.id).then((outcome) => said(memoryNote(outcome)))}>
              Reject
            </KitButton>
          </>
        )}
      </div>
      {item.kind === 'rule' && item.proposalId === undefined && !editing && note === undefined && <p className="text-footnote text-muted">{`Confirming a rule proposes it. It holds once you sign it on the island with ${words.keyTitle}.`}</p>}
      {note !== undefined && <p className="text-footnote text-muted">{note}</p>}
    </article>
  );
}
