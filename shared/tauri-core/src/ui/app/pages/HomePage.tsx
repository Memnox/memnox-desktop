import { ArrowRight } from 'lucide-react';
import { useEffect } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { ago, cardStatus, cardTitle } from '../../../core/domain/session-text';
import { inLine, projectName } from '../../../core/domain/project-context';
import { isActive } from '../../../core/domain/session-status';
import { greeting } from '../../../core/domain/setup-steps';
import { BrandLogo } from '../../kit/logos';
import { useObserved, usePreferences, type SettingsParts } from '../../settings/parts';
import { OverviewPage } from '../../settings/pages/OverviewPage';
import { routeForPage } from '../../../core/domain/destinations';
import { homeMode, modeBadge } from '../../../core/domain/home-steps';
import { HomeStart } from './HomeStart';
import { TodayPage } from './TodayPage';
import { Panel, ReadFailed, Row, Section, StatusWord } from '../widgets';

const RECENT_SESSIONS = 5;

/**
 * Home is the one page the window opens on: the greeting, the getting started steps, then what Today showed in the
 * console's home order. No charts, and every number is a count the ledger can show.
 */
export function HomePage({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { home, sessions, preferences, host, projects } = parts;
  useObserved(home, sessions, projects);
  usePreferences();
  useEffect(() => {
    void home.refresh();
    sessions.start();
    return () => sessions.stop();
  }, []);
  useEffect(() => host.onHomeStale?.(() => home.refreshSoon()), []);
  // Live rows count into today's actions as they happen, with no read each second.
  useEffect(() => host.onLiveActivity?.((rows, missed) => home.heard(rows.length + missed)), []);

  // Until setup is done, the first run's checklist is what Home has to say.
  if (!preferences.setupDone) {
    return <OverviewPage parts={parts} go={(page) => go(routeForPage(page) ?? { destination: 'settings', tab: page })} />;
  }

  const view = home.home;
  const recent = sessions.state.cards.filter((card) => !isActive(cardStatus(card))).slice(0, RECENT_SESSIONS);
  const lead = (
    <>
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h1 className="text-title font-bold text-foreground">{greeting(preferences.name)}</h1>
          <p className="text-footnote text-muted">What your agents can do on their own, and what still needs you.</p>
        </div>
        <Standing mode={homeMode(view?.mode)} read={view !== undefined} away={home.unavailable} />
      </header>

      {home.unavailable && view === undefined && <ReadFailed what="the runtime" retry={() => void home.refresh()} />}

      {/* The getting started steps, as the cloud console's home lists them, above the blocks until every one is done. */}
      <HomeStart parts={parts} go={go} actions={view?.today.actions ?? 0} mode={homeMode(view?.mode)} />
    </>
  );
  const trail = (
    <>
      {/* The count tiles and This week are left off for now, so Home stays on what needs the person and where to carry on. */}
      {recent.length > 0 && (
        <Section title="Carry on">
          <Panel>
            {recent.map((card) => (
              <Row
                key={card.sessionId}
                leading={<BrandLogo agent={card.agent} name={card.agentName} size={26} />}
                title={cardTitle(card)}
                caption={[card.agentName, inLine(projectName(card.repository, projects.projects ?? [])), ago(card.lastActive, Date.now())].filter((part) => part !== undefined).join(' · ')}
                onClick={() => host.openLive?.(card.sessionId)}
              />
            ))}
          </Panel>
        </Section>
      )}

    </>
  );
  // Learn is left off for now, so no row under Waiting on you leads to it.
  return <TodayPage parts={parts} width={width} go={go} lead={lead} waitingFoot={null} trail={trail} />;
}

/** The mode the runtime reported, as the Mac's badge beside the greeting says it, or whether the runtime answers at all. */
function Standing({ mode, read, away }: { mode: ReturnType<typeof homeMode>; read: boolean; away: boolean }) {
  if (mode !== undefined) return <StatusWord tone={mode === 'enforce' ? 'good' : 'attention'}>{modeBadge(mode)}</StatusWord>;
  if (read) return <StatusWord tone="good">Runtime protecting this computer</StatusWord>;
  if (away) return <StatusWord tone="bad">The runtime is not answering</StatusWord>;
  return null;
}

export function GoLink({ onClick, children }: { onClick: () => void; children: string }) {
  return (
    <button type="button" className="mx-focus inline-flex cursor-pointer items-center gap-1 self-start text-footnote font-medium text-primary hover:underline" onClick={onClick}>
      {children}
      <ArrowRight size={12} />
    </button>
  );
}
