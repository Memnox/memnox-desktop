import { ArrowRight, CircleAlert, Hand, ShieldCheck, Sparkles } from 'lucide-react';
import { useEffect } from 'react';
import type { Route } from '../../../core/domain/destinations';
import { HomeLines } from '../../../core/domain/home-lines';
import { ago, cardStatus, cardTitle, repositoryName } from '../../../core/domain/session-text';
import { isActive, statusLabel } from '../../../core/domain/session-status';
import { greeting } from '../../../core/domain/setup-steps';
import { islandWindow } from '../../adapters/tauri-island-window';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, usePreferences, type SettingsParts } from '../../settings/parts';
import { OverviewPage } from '../../settings/pages/OverviewPage';
import { routeForPage } from '../../../core/domain/destinations';
import { EmptyState, Panel, ReadFailed, Row, Section, StatTile, StatusWord } from '../widgets';

const RECENT_SESSIONS = 5;

/**
 * Home answers three things before anything else: what is running, what needs the person, and where they
 * can carry on. No charts, and every number is a count the ledger can show.
 */
export function HomePage({ parts, go }: { parts: SettingsParts; go: (route: Route) => void }) {
  const { home, sessions, preferences, host } = parts;
  useObserved(home, sessions);
  usePreferences();
  useEffect(() => {
    void home.refresh();
    sessions.start();
    return () => sessions.stop();
  }, []);
  useEffect(() => host.onHomeStale?.(() => home.refreshSoon()), []);

  // Until setup is done, the first run's checklist is what Home has to say.
  if (!preferences.setupDone) {
    return <OverviewPage parts={parts} go={(page) => go(routeForPage(page) ?? { destination: 'settings', tab: page })} />;
  }

  const view = home.home;
  const running = sessions.state.cards.filter((card) => isActive(cardStatus(card)));
  const recent = sessions.state.cards.filter((card) => !isActive(cardStatus(card))).slice(0, RECENT_SESSIONS);
  return (
    <div className="flex flex-col gap-7">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h1 className="text-title font-bold text-foreground">{greeting(preferences.name)}</h1>
          <p className="text-footnote text-muted">Your agents at a glance.</p>
        </div>
        {view !== undefined ? <StatusWord tone="good">Runtime protecting this computer</StatusWord> : home.unavailable ? <StatusWord tone="bad">The runtime is not answering</StatusWord> : null}
      </header>

      {home.unavailable && view === undefined && <ReadFailed what="the runtime" retry={() => void home.refresh()} />}

      <div className="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-3">
        <StatTile value={running.length} label={running.length === 1 ? 'Agent working' : 'Agents working'} tone={running.length > 0 ? 'good' : 'quiet'} onClick={() => go({ destination: 'agents', tab: 'sessions' })} />
        <StatTile value={view?.today.actions ?? 0} label="Actions today" />
        <StatTile value={view?.waiting ?? 0} label="Waiting on you" tone={(view?.waiting ?? 0) > 0 ? 'attention' : 'quiet'} onClick={() => go({ destination: 'governance', tab: 'approvals' })} />
      </div>

      <Section title="Running agents" trailing={<GoLink onClick={() => go({ destination: 'agents', tab: 'sessions' })}>All sessions</GoLink>}>
        {running.length === 0 ? (
          <EmptyState icon={Sparkles} title="Nothing is running right now" body="Start Claude Code, Codex or any agent you use, and it appears here while it works." />
        ) : (
          <Panel>
            {running.map((card) => (
              <Row
                key={card.sessionId}
                leading={<BrandLogo agent={card.agent} name={card.agentName} size={30} />}
                title={card.agentName}
                caption={[cardTitle(card), repositoryName(card.repository)].filter((part) => part !== undefined).join(' in ')}
                trailing={<StatusWord tone="good">{statusLabel(cardStatus(card))}</StatusWord>}
                onClick={() => host.openLive?.(card.sessionId)}
              />
            ))}
          </Panel>
        )}
      </Section>

      <Attention parts={parts} go={go} />

      {recent.length > 0 && (
        <Section title="Carry on">
          <Panel>
            {recent.map((card) => (
              <Row
                key={card.sessionId}
                leading={<BrandLogo agent={card.agent} name={card.agentName} size={26} />}
                title={cardTitle(card)}
                caption={[card.agentName, repositoryName(card.repository), ago(card.lastActive, Date.now())].filter((part) => part !== undefined).join(' · ')}
                onClick={() => host.openLive?.(card.sessionId)}
              />
            ))}
          </Panel>
        </Section>
      )}

      {view !== undefined && <p className="text-footnote text-muted">{HomeLines.today(view.today)}</p>}
    </div>
  );
}

/** Everything that waits on the person, in one place to clear, and nothing when nothing waits. */
function Attention({ parts, go }: { parts: SettingsParts; go: (route: Route) => void }) {
  const { home, words } = parts;
  const view = home.home;
  if (view === undefined) return null;
  const needs = view.needsYou ?? [];
  const nothing = view.waiting === 0 && needs.length === 0 && view.ready === undefined && view.notCovered.unprotected === 0;
  if (nothing) return null;
  return (
    <Section title="Needs your attention">
      <Panel>
        {view.waiting > 0 && (
          <Row
            leading={<Hand size={18} className="text-warm" />}
            title={HomeLines.waiting(view.waiting)}
            trailing={<KitButton onClick={() => islandWindow.openFromSettings()}>Answer</KitButton>}
          />
        )}
        {needs.map((line) => (
          <Row key={line} leading={<CircleAlert size={18} className="text-warm" />} title={line} />
        ))}
        {view.ready !== undefined && (
          <Row
            leading={<ArrowRight size={18} className="text-primary" />}
            title={HomeLines.ready(view.ready)}
            caption={view.ready.because}
            trailing={
              <KitButton kind="primary" disabled={home.handingOver} onClick={() => view.ready !== undefined && void home.handOver(view.ready, words.keyTitle)}>
                {home.handingOver ? 'Proposing' : 'Let it run on its own'}
              </KitButton>
            }
          />
        )}
        {view.notCovered.unprotected > 0 && (
          <Row
            leading={<ShieldCheck size={18} className="text-warm" />}
            title={HomeLines.notCovered(view.notCovered)[0] ?? ''}
            trailing={
              <KitButton kind="primary" disabled={home.protecting} onClick={() => void home.protect()}>
                {home.protecting ? 'Protecting' : 'Protect my agents'}
              </KitButton>
            }
          />
        )}
      </Panel>
      {home.handOverNote !== undefined && <p className="text-footnote text-muted">{home.handOverNote}</p>}
      {view.waiting > 0 && <GoLink onClick={() => go({ destination: 'governance', tab: 'approvals' })}>See every approval</GoLink>}
    </Section>
  );
}

export function GoLink({ onClick, children }: { onClick: () => void; children: string }) {
  return (
    <button type="button" className="mx-focus inline-flex cursor-pointer items-center gap-1 self-start text-footnote font-medium text-primary hover:underline" onClick={onClick}>
      {children}
      <ArrowRight size={12} />
    </button>
  );
}
