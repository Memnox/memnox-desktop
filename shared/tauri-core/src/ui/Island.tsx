import { useState, useSyncExternalStore } from 'react';
import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';
import type { HeldCalls, HeldOutcome, ProposalCards, Talking } from '../core';
import { Cards } from './Cards';
import { Talk } from './Talk';

/** What the island says after a press, in the person's words rather than the daemon's. */
function told(outcome: HeldOutcome): string | undefined {
  switch (outcome.kind) {
    case 'answered':
      return undefined;
    case 'answered-elsewhere':
      return outcome.earlier.line;
    case 'cancelled':
      return 'Nothing was sent, so it is still waiting.';
    case 'failed':
      return `That did not go through: ${outcome.why}`;
  }
}

/** The island: the held call on screen, how many wait, and the three answers. Draws the core's state and nothing else. */
export function Island({ calls, talking, cards }: { calls: HeldCalls; talking: Talking; cards: ProposalCards }) {
  const state = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const [note, setNote] = useState<string>();
  const [busy, setBusy] = useState(false);
  const shown = state.waiting.shown;

  async function answer(subject: string, choice: HoldAnswer) {
    setBusy(true);
    setNote(undefined);
    // Answered by hand, so the voice stops asking about it.
    talking.answeredByHand(subject);
    setNote(told(await calls.answer(subject, choice)));
    setBusy(false);
  }

  if (shown === undefined) {
    return (
      <main className="island island--quiet" data-connected={state.connected}>
        <span className="orb" aria-hidden />
        <span className="quiet">{state.connected ? 'Nothing waits on you' : 'Waiting for Memnox to start'}</span>
        <Cards cards={cards} />
        <Talk talking={talking} />
        {note !== undefined && <p className="note">{note}</p>}
      </main>
    );
  }

  const card = shown.card;
  return (
    <main className="island" aria-live="polite">
      <header>
        <span className="orb orb--needs-you" aria-hidden />
        <span className="who">{card.label} needs you</span>
        {state.waiting.positionText !== undefined && <span className="count">{state.waiting.positionText}</span>}
      </header>
      {state.waiting.header !== undefined && <p className="waiting">{state.waiting.header}</p>}
      <p className="what">{card.what}</p>
      {card.why !== undefined && <p className="why">{card.why}</p>}
      {card.place !== undefined && <p className="place">in {card.place}</p>}
      <nav className="answers">
        <button disabled={busy} onClick={() => void answer(card.subject, HOLD_ANSWER.DENY)}>
          Deny
        </button>
        <button disabled={busy} onClick={() => void answer(card.subject, HOLD_ANSWER.SESSION)}>
          This session
        </button>
        <button className="primary" disabled={busy} onClick={() => void answer(card.subject, HOLD_ANSWER.ONCE)}>
          Allow once
        </button>
      </nav>
      <footer>
        <button className="step" disabled={!state.waiting.canStepNewer} onClick={() => calls.step(-1)} aria-label="Newer">
          ‹
        </button>
        <span className="sign">{card.withinSession ? 'Stays in its repository' : 'Asks you to confirm before it goes'}</span>
        <button className="step" disabled={!state.waiting.canStepOlder} onClick={() => calls.step(1)} aria-label="Older">
          ›
        </button>
      </footer>
      <Cards cards={cards} />
      <Talk talking={talking} />
      {note !== undefined && <p className="note">{note}</p>}
    </main>
  );
}
