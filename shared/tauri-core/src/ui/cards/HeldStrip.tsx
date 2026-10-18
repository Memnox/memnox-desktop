import { useState, useSyncExternalStore } from 'react';
import { HOLD_ANSWER } from '@memnox/core/wire';
import type { HeldCalls, HeldCard, HeldOutcome } from '../../core';
import { ANSWERING_ROW, BrandLogo, SFSymbol } from '../kit';
import { SYSTEM_MONO } from './MarkdownText';

/**
 * `HeldStrip`: a call waiting on the person, answered where it is read, inside a window such as the live
 * session: who asks and the command, then Deny beside Allow once, which asks for the key when the call
 * reaches outside its session. It answers through the held calls' own signed path, so a yes from a
 * window is signed exactly as a yes from the island. No Return shortcut, since a stray key must never allow.
 */
export function HeldStrip({ calls, card, onAnswered }: { calls: HeldCalls; card: HeldCard; onAnswered?: (outcome: HeldOutcome) => void }) {
  const answering = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state.answering,
  );
  const [said, setSaid] = useState<string>();

  async function press(answer: typeof HOLD_ANSWER.DENY | typeof HOLD_ANSWER.ONCE) {
    const outcome = await calls.answer(card.subject, answer);
    setSaid(outcome.kind === 'failed' ? `That did not go through: ${outcome.why}` : outcome.kind === 'cancelled' ? 'Nothing was sent, so it is still waiting.' : undefined);
    onAnswered?.(outcome);
  }

  return (
    <div className="flex flex-col gap-2.5 rounded-island bg-surface p-3" style={{ boxShadow: 'inset 0 0 0 1px rgb(255 159 10 / 0.62)' }}>
      <div className="flex min-w-0 items-center gap-2">
        <BrandLogo agent={card.agent} name={card.who} size={22} />
        <span className="shrink-0 text-body font-semibold text-ink">{card.who}</span>
        <span className="min-w-0 truncate text-body text-ink-secondary">{card.why ?? 'is waiting on you'}</span>
      </div>
      <p className={`m-0 line-clamp-2 w-full rounded-lg bg-ink-faint-fill p-2 ${SYSTEM_MONO} text-footnote text-ink [overflow-wrap:anywhere]`} title={card.what}>
        {card.what}
      </p>
      <div className={`flex items-center gap-2 ${answering ? ANSWERING_ROW : ''}`}>
        <button type="button" className="inline-flex cursor-pointer items-center rounded-full bg-[var(--mx-ink-fill-09,rgb(255_255_255/0.09))] px-3.5 py-[7px] text-button font-medium text-ink active:scale-[0.94]" disabled={answering} onClick={() => void press(HOLD_ANSWER.DENY)}>
          Deny
        </button>
        <button type="button" className="inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-primary-fill px-3.5 py-[7px] text-button font-medium text-primary-text active:scale-[0.94]" disabled={answering} onClick={() => void press(HOLD_ANSWER.ONCE)}>
          {card.touchID && <SFSymbol name="touchid" size={12} />}
          Allow once
        </button>
      </div>
      {said !== undefined && <p className="m-0 text-caption text-ink-secondary">{said}</p>}
    </div>
  );
}
