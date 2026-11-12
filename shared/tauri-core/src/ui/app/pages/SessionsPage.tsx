import type { SessionCard } from '@memnox/core/wire';
import { Bot } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { WidthClass } from '../../../core/domain/destinations';
import { ago, cardStatus, cardTitle, repositoryName } from '../../../core/domain/session-text';
import { SESSION_STATUS_ORDER, statusLabel, type SessionStatus } from '../../../core/domain/session-status';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Inspector } from '../widgets';
import { usePicked } from '../inspector-host';
import { SessionsTabLines } from '../../../core/domain/agent-lines';
import { forSession, shownAs, workLabel, workReason, WorkCorrelationLines, type WorkCorrelation } from '../../../core/domain/work-correlations';
import { BrandLogo, Button, EmptyState, Panel, Row, Section, StatusWord, type Tone } from '../../kit';

/** One group per status, in the order every surface reads them. */
const GROUPS: readonly { title: string; holds: readonly SessionStatus[] }[] = SESSION_STATUS_ORDER.map((status) => ({ title: statusLabel(status), holds: [status] }));

/** An agent's logo at the head of its row, and larger at the head of its details. */
const ROW_LOGO = 28;
const DETAIL_LOGO = 36;
/** Issues move as runs work, so an open page asks again now and then; nothing is asked with no account. */
const WORK_REFRESH_MS = 15_000;

/** Which issue each listed session concerns, read again while the page is open and whenever the sessions change. */
function useSessionWork(parts: SettingsParts, sessionIds: readonly string[]): readonly WorkCorrelation[] {
  const [work, setWork] = useState<readonly WorkCorrelation[]>([]);
  const key = [...sessionIds].sort().join(',');
  useEffect(() => {
    let live = true;
    const read = () => void parts.workspaceAgents.workOf(sessionIds).then((found) => live && setWork(found));
    read();
    const timer = setInterval(read, WORK_REFRESH_MS);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [key]);
  return work;
}

export function toneOf(status: SessionStatus): Tone {
  if (status === 'stopped') return 'bad';
  if (status === 'needs-you' || status === 'finished') return 'attention';
  if (status === 'working') return 'good';
  return 'quiet';
}

/** Sessions: every session on this computer, grouped by status in the order every surface reads them. */
export function SessionsPage({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { sessions, host } = parts;
  useObserved(sessions);
  useEffect(() => {
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [chosen, choose] = usePicked();
  const cards = sessions.state.cards;
  const picked = cards.find((card) => card.sessionId === chosen);
  const work = useSessionWork(parts, cards.map((card) => card.sessionId));

  if (cards.length === 0) {
    return <EmptyState icon={Bot} title={SessionsTabLines.emptyTitle} body={SessionsTabLines.emptyBody} />;
  }
  return (
    <div className="flex min-h-0 gap-0">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        {GROUPS.map((group) => {
          const held = cards.filter((card) => group.holds.includes(cardStatus(card)));
          if (held.length === 0) return null;
          return (
            <Section key={group.title} title={SessionsTabLines.grouped(group.title, held.length)}>
              <Panel>
                {held.map((card) => (
                  <SessionRow key={card.sessionId} card={card} work={forSession(work, card.sessionId)} chosen={card.sessionId === chosen} pick={() => choose(card.sessionId)} />
                ))}
              </Panel>
            </Section>
          );
        })}
      </div>
      {picked !== undefined && (
        <Inspector title={picked.agentName} width={width} close={() => choose(undefined)} item={picked.sessionId}>
          <SessionDetail card={picked} work={forSession(work, picked.sessionId)} openPage={(url) => host.openPage(url)} open={() => host.openLive?.(picked.sessionId)} />
        </Inspector>
      )}
    </div>
  );
}

function SessionRow({ card, work, chosen, pick }: { card: SessionCard; work: readonly WorkCorrelation[]; chosen: boolean; pick: () => void }) {
  const status = cardStatus(card);
  const issues = work.map(workLabel).join(', ');
  return (
    <Row
      chosen={chosen}
      leading={<BrandLogo agent={card.agent} name={card.agentName} size={ROW_LOGO} />}
      title={cardTitle(card)}
      caption={[card.agentName, repositoryName(card.repository), issues === '' ? undefined : issues, ago(card.lastActive, Date.now())].filter((part) => part !== undefined).join(' · ')}
      trailing={<StatusWord tone={toneOf(status)}>{statusLabel(status)}</StatusWord>}
      onClick={pick}
    />
  );
}

/** The issues a session concerns, each saying what its match rests on, with the one rule behind every match. */
function SessionIssues({ work, openPage }: { work: readonly WorkCorrelation[]; openPage: (url: string) => void }) {
  if (work.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      <span className="text-footnote text-muted">{WorkCorrelationLines.heading}</span>
      {work.map((each) => (
        <div key={each.id} className="flex flex-col gap-0.5">
          {shownAs(each) === 'linked' && each.visible && each.item !== undefined ? (
            <Button kind="link" onClick={() => openPage(each.item?.url ?? '')}>
              {workLabel(each)}
            </Button>
          ) : (
            <StatusWord tone={shownAs(each) === 'ambiguous' ? 'attention' : 'quiet'}>{workLabel(each)}</StatusWord>
          )}
          {workReason(each) !== undefined && <span className="text-meta text-muted">{workReason(each)}</span>}
        </div>
      ))}
      <span className="text-meta text-muted">{WorkCorrelationLines.explain}</span>
    </div>
  );
}

function SessionDetail({ card, work, openPage, open }: { card: SessionCard; work: readonly WorkCorrelation[]; openPage: (url: string) => void; open: () => void }) {
  const status = cardStatus(card);
  const facts: [string, string | undefined][] = [
    [SessionsTabLines.status, statusLabel(status)],
    [SessionsTabLines.workingOn, card.focus ?? card.task],
    [SessionsTabLines.repository, repositoryName(card.repository)],
    [SessionsTabLines.runningIn, card.where ?? card.runningIn],
    [SessionsTabLines.started, ago(card.startedAt, Date.now())],
    [SessionsTabLines.lastActive, ago(card.lastActive, Date.now())],
    [SessionsTabLines.actions, card.actions === undefined ? undefined : String(card.actions)],
  ];
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-3">
        <BrandLogo agent={card.agent} name={card.agentName} size={DETAIL_LOGO} />
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-body font-semibold text-foreground">{cardTitle(card)}</span>
          <StatusWord tone={toneOf(status)}>{statusLabel(status)}</StatusWord>
        </div>
      </div>
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-footnote">
        {facts
          .filter((fact): fact is [string, string] => fact[1] !== undefined)
          .map(([name, value]) => (
            <div key={name} className="contents">
              <dt className="text-muted">{name}</dt>
              <dd className="min-w-0 break-words text-foreground">{value}</dd>
            </div>
          ))}
      </dl>
      <SessionIssues work={work} openPage={openPage} />
      <Button kind="primary" onClick={open}>
        {SessionsTabLines.openLive}
      </Button>
    </div>
  );
}
