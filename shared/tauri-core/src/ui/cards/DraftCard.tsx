import { useEffect, useState, type ReactNode } from 'react';
import type { MailDraft } from '@memnox/core/wire';
import { ANSWERING_ROW, IslandButton, IslandCard, PRESSABLE, SFSymbol, VEIL } from '../kit';

/** Gmail's own send blue, which the mail draft's Send wears rather than the tool colour. */
const MAIL_SEND = '#1A73E8';
/** The mail's red, on its envelope. */
const MAIL_RED = '#EA4335';
/** The body types in over about 1.1 s at 60 frames, at least two characters a frame. */
const TYPE_IN_MS = 1100;
const FRAME_MS = 1000 / 60;

/** How many characters the body shows after `elapsed` of typing in. */
export function typedLength(length: number, elapsed: number): number {
  const frames = Math.max(1, Math.round(TYPE_IN_MS / FRAME_MS));
  const perFrame = Math.max(2, Math.ceil(length / frames));
  return Math.min(length, Math.floor(elapsed / FRAME_MS) * perFrame);
}

/**
 * `IslandDraftCard`: a mail laid out as a mail app lays it out, its body typed in, Send signed. The Mac
 * switches this card off for now (`showsDrafts = false`), so the island never routes to it either; it is
 * here so turning it on is one line on both.
 */
export function DraftCard({ draft, onAnswer, sending = false, className }: { draft: MailDraft; onAnswer: (send: boolean) => void; sending?: boolean; className?: string }) {
  const [typed, setTyped] = useState(0);
  useEffect(() => {
    const started = performance.now();
    let frame = requestAnimationFrame(function step(now) {
      const shown = typedLength(draft.body.length, now - started);
      setTyped(shown);
      if (shown < draft.body.length) frame = requestAnimationFrame(step);
    });
    return () => cancelAnimationFrame(frame);
  }, [draft.body]);
  const reply = draft.mode === 'reply';
  const typing = typed < draft.body.length;
  return (
    <IslandCard veil={VEIL.draft} className={`flex flex-col px-3.5 pb-3.5 ${className ?? ''}`}>
      <div className="flex h-[42px] shrink-0 items-center gap-2 pt-2">
        <span className="grid" style={{ color: MAIL_RED }}>
          <SFSymbol name="envelope.fill" size={16} />
        </span>
        {reply && (
          <span className="grid text-white/[0.62]">
            <SFSymbol name="arrowshape.turn.up.left" size={13} />
          </span>
        )}
        <span className="text-callout font-semibold text-white">{reply ? 'Reply' : 'New Message'}</span>
        <span className="flex-1" />
        <button type="button" className={`${PRESSABLE} grid size-6 place-items-center rounded-full bg-white/10 text-white/[0.92]`} disabled={sending} onClick={() => onAnswer(false)} title="Close without sending" aria-label="Close without sending">
          <SFSymbol name="xmark" size={12} weight="bold" />
        </button>
      </div>
      {draft.thread !== undefined && (
        <Row>
          <span className="flex items-center gap-1 text-body font-medium text-white/[0.62]">
            View thread ({draft.thread}) <SFSymbol name="chevron.down" size={11} />
          </span>
        </Row>
      )}
      <Row>
        <People label="To" people={draft.to} />
      </Row>
      {draft.cc !== undefined && draft.cc.length > 0 && (
        <Row>
          <People label="Cc" people={draft.cc} />
        </Row>
      )}
      {draft.subject !== undefined && (
        <Row>
          <span className="truncate text-callout font-semibold text-white">{draft.subject}</span>
        </Row>
      )}
      <p className="m-0 min-h-0 flex-1 overflow-y-auto whitespace-pre-wrap py-2.5 text-callout leading-[21px] text-white/[0.92] [scrollbar-width:none]">
        {draft.body.slice(0, typed)}
        {typing && <span className="ml-px inline-block h-4 w-[1.5px] translate-y-[3px] animate-caret bg-white" />}
      </p>
      <div className={`flex items-center gap-2 ${sending ? ANSWERING_ROW : ''}`}>
        <IslandButton inRow onClick={() => void navigator.clipboard?.writeText(draft.body)} aria-label="Copy the message" title="Copy the message">
          <SFSymbol name="doc.on.doc" size={12} />
        </IslandButton>
        <span className="flex-1" />
        <button type="button" className={`${PRESSABLE} inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-callout font-semibold text-white`} style={{ backgroundColor: MAIL_SEND }} onClick={() => onAnswer(true)}>
          <SFSymbol name="touchid" size={14} />
          Send
        </button>
      </div>
    </IslandCard>
  );
}

/** One 34 tall row of the mail's head, under a white 7% rule. */
function Row({ children }: { children: ReactNode }) {
  return <div className="flex h-[34px] shrink-0 items-center border-t border-white/[0.07]">{children}</div>;
}

function People({ label, people }: { label: string; people: readonly string[] }) {
  return (
    <span className="flex min-w-0 items-center gap-2">
      <span className="text-body text-white/[0.62]">{label}</span>
      {people.map((person) => (
        <span key={person} className="truncate rounded-full bg-white/10 px-2.5 py-1 text-body font-medium text-white">
          {person}
        </span>
      ))}
    </span>
  );
}
