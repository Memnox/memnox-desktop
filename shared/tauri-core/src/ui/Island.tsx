import { useRef, useState, useSyncExternalStore } from 'react';
import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';
import { Check, ChevronLeft, ChevronRight, ClockArrowUp, Settings as Gear, ShieldCheck, X } from 'lucide-react';
import type { HeldCalls, HeldOutcome, OrbState, ProposalCards, Setup, Talking, VoiceSettings } from '../core';
import { Cards } from './Cards';
import { Orb, type OrbHandle } from './Orb';
import { Settings } from './Settings';
import { SetupRow } from './SetupRow';
import { Talk } from './Talk';
import { button, note } from './ui';

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

/** The island: the orb, the held call on screen, how many wait, and the three answers. Draws the core's state and nothing else. */
export interface IslandParts {
  calls: HeldCalls;
  talking: Talking;
  cards: ProposalCards;
  setup: Setup;
  voiceSettings: VoiceSettings;
  /** Opens on the settings, for the preview page. */
  settingsOpen?: boolean;
}

export function Island({ calls, talking, cards, setup, voiceSettings, settingsOpen = false }: IslandParts) {
  const state = useSyncExternalStore(
    (changed) => calls.observe(changed),
    () => calls.state,
  );
  const talk = useSyncExternalStore(
    (changed) => talking.observe(changed),
    () => talking.state,
  );
  const [said, setSaid] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [settings, setSettings] = useState(settingsOpen);
  const orb = useRef<OrbHandle>();
  const shown = state.waiting.shown;
  const orbState: OrbState = shown !== undefined ? 'needs-you' : talk.phase;

  async function answer(subject: string, choice: HoldAnswer) {
    setBusy(true);
    setSaid(undefined);
    // Answered by hand, so the voice stops asking about it.
    talking.answeredByHand(subject);
    const outcome = await calls.answer(subject, choice);
    orb.current?.react(outcome.kind === 'failed' ? 'stumble' : outcome.kind !== 'answered' ? 'settle' : choice === HOLD_ANSWER.DENY ? 'refused' : 'allowed');
    setSaid(told(outcome));
    setBusy(false);
  }

  return (
    <main className="mx-auto grid max-h-[calc(100vh-8px)] max-w-[400px] gap-2 overflow-y-auto rounded-[22px] bg-ground px-4 py-3 font-sans text-[13px] text-ink shadow-[0_8px_28px_rgb(0_0_0/35%)]" aria-live="polite">
      <header className="flex items-center gap-2.5">
        <Orb side={shown !== undefined ? 36 : 28} state={orbState} waiting={shown !== undefined} handle={(handle) => (orb.current = handle)} />
        {shown === undefined ? (
          <span className="flex-1 text-muted">{state.connected ? 'Nothing waits on you' : 'Waiting for Memnox to start'}</span>
        ) : (
          <>
            <span className="flex-1 font-semibold">{shown.card.label} needs you</span>
            {state.waiting.positionText !== undefined && <span className="text-muted">{state.waiting.positionText}</span>}
          </>
        )}
        <button className={button('icon')} onClick={() => setSettings(!settings)} aria-label="Settings" aria-pressed={settings}>
          <Gear size={15} />
        </button>
      </header>
      <SetupRow setup={setup} />
      {shown !== undefined && (
        <section className="grid gap-1.5">
          {state.waiting.header !== undefined && <p className="text-muted">{state.waiting.header}</p>}
          <p className="text-[15px] font-semibold">{shown.card.what}</p>
          {shown.card.why !== undefined && <p className="text-muted">{shown.card.why}</p>}
          {shown.card.place !== undefined && <p className="text-muted">in {shown.card.place}</p>}
          <nav className="mt-1.5 grid grid-cols-3 gap-2">
            <button className={button('quiet')} disabled={busy} onClick={() => void answer(shown.card.subject, HOLD_ANSWER.DENY)}>
              <X size={14} /> Deny
            </button>
            <button className={button('quiet')} disabled={busy} onClick={() => void answer(shown.card.subject, HOLD_ANSWER.SESSION)}>
              <ClockArrowUp size={14} /> Session
            </button>
            <button className={button('primary')} disabled={busy} onClick={() => void answer(shown.card.subject, HOLD_ANSWER.ONCE)}>
              <Check size={14} /> Allow once
            </button>
          </nav>
          <footer className="flex items-center justify-between text-xs text-muted">
            <button className={button('icon')} disabled={!state.waiting.canStepNewer} onClick={() => calls.step(-1)} aria-label="Newer">
              <ChevronLeft size={16} />
            </button>
            <span className="flex items-center gap-1.5">
              <ShieldCheck size={13} />
              {shown.card.withinSession ? 'Stays in its repository' : 'Asks you to confirm before it goes'}
            </span>
            <button className={button('icon')} disabled={!state.waiting.canStepOlder} onClick={() => calls.step(1)} aria-label="Older">
              <ChevronRight size={16} />
            </button>
          </footer>
        </section>
      )}
      <Cards cards={cards} />
      {settings && <Settings voiceSettings={voiceSettings} setup={setup} />}
      <Talk talking={talking} />
      {said !== undefined && <p className={note}>{said}</p>}
    </main>
  );
}
