import { HOLD_ANSWER } from '@memnox/core/wire';
import { ShieldCheck, TriangleAlert } from 'lucide-react';
import { CONNECTION_PAGE, RuntimeAwayLines } from '../../../core/domain/runtime-away';
import { useEffect, useState } from 'react';
import { HeldImpactLines } from '../../cards/HeldImpact';
import { NOTICES_ASKED_KEY, NOTICES_DENIED, NOTICES_DETAIL, NOTICES_KEY, NOTICES_TITLE } from '../../../core/domain/held-notices';
import { useObserved, type SettingsParts } from '../../settings/parts';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { ActivityPage } from './ActivityPage';
import { LearnPage } from './LearnPage';
import { PoliciesPage } from './PoliciesPage';
import { projectNameOfPlace } from '../../../core/domain/project-context';
import { heldFacts, NOTHING_WAITING, NOTHING_WAITING_DETAIL, waitingLine } from '../../../core/domain/approvals-lines';
import { GovernanceLines } from '../../../core/domain/governance-lines';
import { BrandLogo, Button, EmptyState, StatusWord, Switch } from '../../kit';
import { handHeld, heldBusy } from '../held-hand';
import { needsYou, openWork } from '../../../core/domain/agent-work-lines';
import { waitingHandoffs } from '../../../core/domain/workspace-agents';
import { WorkNeedingYou } from './WorkTab';
import { WorkspaceHandoffs } from './WorkspaceAgents';

/** How long the window waits before opening the live feed again after the daemon went away. */
const RECONNECT_MS = 2_000;

/** The asking agent's logo at the head of its card. */
const CARD_LOGO = 26;

export function GovernancePage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  if (tab === 'policies') return <PoliciesPage parts={parts} width={width} />;
  if (tab === 'activity') return <ActivityPage parts={parts} width={width} go={go} />;
  if (tab === 'learn') return <LearnPage parts={parts} />;
  return <Approvals parts={parts} />;
}

/**
 * What waits on the person, oldest first, each saying exactly what the agent wants to do and where. Every answer goes
 * through the island, as the Mac's does, so a yes that reaches outside the session is signed exactly as there and how
 * it ended is said on the island's card; the card here leaves once the answer stands.
 */
function Approvals({ parts }: { parts: SettingsParts }) {
  const { calls, words, projects, support, work, workspaceAgents, home, host } = parts;
  useObserved(calls, projects, work, workspaceAgents, support, home);
  const offersWork = support.supports('agent-work') === true;
  useEffect(() => {
    // The projects name where each call waits, so a person with several sees which one it is in.
    if (support.supports('projects') === true && projects.projects === undefined) void projects.refresh();
  }, []);
  useEffect(() => {
    // Handoffs and done claims wait here too, beside the held calls.
    if (offersWork) void work.refresh();
  }, [offersWork]);
  useEffect(() => parts.host.onLiveWork?.((changed) => work.heard(changed)), []);
  // Whether the runtime answers, so an empty page never says all clear while nothing could reach it.
  useEffect(() => {
    void home.refresh();
  }, []);
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
  const waiting = [...calls.state.waiting.newestFirst].reverse();
  const busy = heldBusy(calls.state);
  const workWaits = (offersWork && openWork(work.work ?? []).some(needsYou)) || (workspaceAgents.signedIn && waitingHandoffs(workspaceAgents.remote).length > 0);

  return (
    <div className="flex flex-col gap-6">
      <NoticesSwitch parts={parts} />
      {waiting.length === 0 ? (
        !workWaits &&
        (home.unavailable ? (
          <EmptyState
            icon={TriangleAlert}
            title={RuntimeAwayLines.title}
            body={RuntimeAwayLines.approvals}
            action={<Button onClick={() => host.openSettings(CONNECTION_PAGE)}>{RuntimeAwayLines.openConnection}</Button>}
          />
        ) : (
          <EmptyState icon={ShieldCheck} title={NOTHING_WAITING} body={NOTHING_WAITING_DETAIL} />
        ))
      ) : (
        <>
          <p className="text-footnote text-muted">{waitingLine(waiting.length)}</p>
          <div className="flex flex-col gap-3">
            {waiting.map(({ card, subject }) => (
              <article key={subject} aria-label={GovernanceLines.asks(card.who)} className="flex flex-col gap-3 rounded-card border border-panel-edge bg-card p-4">
                <header className="flex items-center gap-2.5">
                  <BrandLogo agent={card.agent} name={card.who} size={CARD_LOGO} />
                  <span className="min-w-0 flex-1 truncate text-body font-semibold text-foreground">{card.who}</span>
                  <StatusWord tone="attention">{GovernanceLines.asksFirst}</StatusWord>
                </header>
                <p className="text-body text-foreground select-text">{card.what}</p>
                {/* What the held action could affect, under what it does, as the Mac's card shows it. */}
                {card.impact !== undefined && <HeldImpactLines impact={card.impact} />}
                <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-meta">
                  {heldFacts(card, projectNameOfPlace(card.place, projects.projects ?? []), words.keyTitle).map(([name, value]) => (
                    <Fact key={name} name={name} value={value} />
                  ))}
                </dl>
                <div className="flex items-center gap-2">
                  <Button kind="primary" disabled={busy} onClick={() => handHeld(calls, subject, HOLD_ANSWER.ONCE)}>
                    {GovernanceLines.allowOnce}
                  </Button>
                  <Button disabled={busy} onClick={() => handHeld(calls, subject, HOLD_ANSWER.SESSION)}>
                    {GovernanceLines.allowSession}
                  </Button>
                  {/* Set apart from the yeses, so a refusal is never pressed by a slip. */}
                  <span className="min-w-5 flex-1" />
                  <Button disabled={busy} onClick={() => handHeld(calls, subject, HOLD_ANSWER.DENY)}>
                    {GovernanceLines.deny}
                  </Button>
                </div>
              </article>
            ))}
          </div>
        </>
      )}
      {offersWork && <WorkNeedingYou parts={parts} />}
      <WorkspaceHandoffs parts={parts} />
    </div>
  );
}

/**
 * Whether a held call is said by the system as well, on unless turned off. Turning it on is where the system is
 * asked, so the question comes from the person's own press rather than at launch.
 */
function NoticesSwitch({ parts }: { parts: SettingsParts }) {
  const { host } = parts;
  const [on, setOn] = useState(() => localStorage.getItem(NOTICES_KEY) !== String(false));
  const [denied, setDenied] = useState(false);
  useEffect(() => {
    if (on && host.notices !== undefined) void host.notices(false).then((granted) => setDenied(!granted && localStorage.getItem(NOTICES_ASKED_KEY) === String(true)));
  }, [on]);
  const change = (next: boolean) => {
    localStorage.setItem(NOTICES_KEY, String(next));
    setOn(next);
    if (!next || host.notices === undefined) return;
    localStorage.setItem(NOTICES_ASKED_KEY, String(true));
    void host.notices(true).then((granted) => setDenied(!granted));
  };
  return (
    <div className="flex flex-col gap-1">
      {/* Plain on the page, as the Mac's toggle sits, rather than in a card of its own. */}
      <div className="flex items-center gap-3">
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="text-body font-medium text-foreground">{NOTICES_TITLE}</span>
          <span className="text-footnote text-muted">{NOTICES_DETAIL}</span>
        </div>
        <Switch on={on} label={NOTICES_TITLE} onChange={change} />
      </div>
      {on && denied && (
        <div>
          <StatusWord tone="attention">{NOTICES_DENIED}</StatusWord>
        </div>
      )}
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
