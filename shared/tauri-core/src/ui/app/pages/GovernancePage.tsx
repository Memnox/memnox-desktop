import { HOLD_ANSWER } from '@memnox/core/wire';
import { Bell, ShieldCheck } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { HeldOutcome } from '../../../core/application/held-calls';
import type { HeldCard } from '../../../core/domain/held-card';
import type { HeldAnswer } from '../../../core/domain/call-label';
import { BrandLogo } from '../../kit/logos';
import { KitButton, SwitchRow } from '../../settings/kit';
import { NOTICES_ASKED_KEY, NOTICES_DENIED, NOTICES_DETAIL, NOTICES_KEY, NOTICES_TITLE } from '../../../core/domain/held-notices';
import { useObserved, type SettingsParts } from '../../settings/parts';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { ActivityPage } from './ActivityPage';
import { LearnPage } from './LearnPage';
import { PoliciesPage } from './PoliciesPage';
import { EmptyState, StatusWord } from '../widgets';

/** How long the window waits before opening the live feed again after the daemon went away. */
const RECONNECT_MS = 2_000;

export function GovernancePage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  if (tab === 'policies') return <PoliciesPage parts={parts} width={width} />;
  if (tab === 'activity') return <ActivityPage parts={parts} width={width} go={go} />;
  if (tab === 'learn') return <LearnPage parts={parts} />;
  return <Approvals parts={parts} />;
}

/**
 * What waits on the person, oldest first, each saying exactly what the agent wants to do and where. A yes
 * that reaches outside the session is signed with the computer's key, the same as on the island.
 */
function Approvals({ parts }: { parts: SettingsParts }) {
  const { calls, words } = parts;
  useObserved(calls);
  useEffect(() => {
    let open = true;
    const loop = async () => {
      while (open) {
        await calls.watch();
        if (open) await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
      }
    };
    void loop();
    return () => {
      open = false;
    };
  }, []);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const waiting = [...calls.state.waiting.newestFirst].reverse();

  const answer = async (card: HeldCard, choice: HeldAnswer) => {
    const outcome = await calls.answer(card.subject, choice);
    setNotes((now) => ({ ...now, [card.subject]: outcomeNote(outcome) }));
  };

  if (waiting.length === 0) {
    return (
      <div className="flex flex-col gap-3">
        <NoticesSwitch parts={parts} />
        <EmptyState
          icon={ShieldCheck}
          title="Nothing is waiting on you"
          body={calls.state.connected ? 'When an agent asks before doing something your rules hold, it waits here and on the island.' : 'Memnox is reaching the runtime. Anything held will show here as soon as it answers.'}
        />
      </div>
    );
  }
  return (
    <div className="flex flex-col gap-3">
      <NoticesSwitch parts={parts} />
      <p className="text-footnote text-muted">{`${waiting.length} waiting, oldest first.`}</p>
      {waiting.map(({ card, subject }) => (
        <article key={subject} className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
          <header className="flex items-center gap-2.5">
            <BrandLogo agent={card.agent} name={card.who} size={26} />
            <span className="flex-1 text-body font-semibold text-foreground">{card.who}</span>
            <StatusWord tone="attention">Asks first</StatusWord>
          </header>
          <p className="text-body text-foreground">{card.what}</p>
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-footnote">
            {card.why !== undefined && <Fact name="Why it asks" value={card.why} />}
            {card.task !== undefined && <Fact name="Task" value={card.task} />}
            {card.place !== undefined && <Fact name="Where" value={card.place} />}
            <Fact name="Signed" value={signedFact(card, words.keyTitle)} />
          </dl>
          <div className="flex flex-wrap items-center gap-2">
            <KitButton kind="primary" disabled={calls.state.answering} onClick={() => void answer(card, HOLD_ANSWER.ONCE)}>
              Allow once
            </KitButton>
            <KitButton disabled={calls.state.answering} onClick={() => void answer(card, HOLD_ANSWER.SESSION)}>
              Allow this session
            </KitButton>
            {/* Set apart from the yeses, so a refusal is never pressed by a slip. */}
            <span className="flex-1" />
            <KitButton disabled={calls.state.answering} onClick={() => void answer(card, HOLD_ANSWER.DENY)}>
              Deny
            </KitButton>
          </div>
          {notes[subject] !== undefined && <p className="text-footnote text-muted">{notes[subject]}</p>}
        </article>
      ))}
    </div>
  );
}

/**
 * Whether a held call is said by the system as well, on unless turned off. Turning it on is where the system is
 * asked, so the question comes from the person's own press rather than at launch.
 */
function NoticesSwitch({ parts }: { parts: SettingsParts }) {
  const { host } = parts;
  const [on, setOn] = useState(() => localStorage.getItem(NOTICES_KEY) !== 'false');
  const [denied, setDenied] = useState(false);
  useEffect(() => {
    if (on && host.notices !== undefined) void host.notices(false).then((granted) => setDenied(!granted && localStorage.getItem(NOTICES_ASKED_KEY) === 'true'));
  }, [on]);
  const change = (next: boolean) => {
    localStorage.setItem(NOTICES_KEY, String(next));
    setOn(next);
    if (!next || host.notices === undefined) return;
    localStorage.setItem(NOTICES_ASKED_KEY, 'true');
    void host.notices(true).then((granted) => setDenied(!granted));
  };
  return (
    <div className="flex flex-col gap-1.5 rounded-xl border border-panel-edge bg-card px-4 py-3">
      <SwitchRow icon={Bell} title={NOTICES_TITLE} caption={NOTICES_DETAIL} on={on} onChange={change} />
      {on && denied && <StatusWord tone="attention">{NOTICES_DENIED}</StatusWord>}
    </div>
  );
}

function Fact({ name, value }: { name: string; value: string }) {
  return (
    <>
      <dt className="text-muted">{name}</dt>
      <dd className="min-w-0 break-words text-foreground">{value}</dd>
    </>
  );
}

/** How a yes to this call is signed, and whether the signature covers exactly the call shown. */
function signedFact(card: HeldCard, keyTitle: string): string {
  if (!card.touchID) return 'Inside its own repository, so a yes needs no signature';
  if (card.actionDigest === undefined) return `A yes is signed with ${keyTitle}`;
  return `A yes is signed with ${keyTitle} over exactly this call, so one changed since is refused`;
}

function outcomeNote(outcome: HeldOutcome): string {
  switch (outcome.kind) {
    case 'answered':
      return 'Answered.';
    case 'answered-elsewhere':
      return 'Somebody answered this first, and that answer stands.';
    case 'cancelled':
      return 'Nothing was sent, so it still waits.';
    case 'failed':
      return outcome.why;
  }
}
