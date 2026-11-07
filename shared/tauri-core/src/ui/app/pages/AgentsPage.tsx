import type { SessionCard } from '@memnox/core/wire';
import { Bot } from 'lucide-react';
import { useEffect } from 'react';
import type { WidthClass } from '../../../core/domain/destinations';
import { ago, cardStatus, cardTitle, repositoryName } from '../../../core/domain/session-text';
import { statusLabel, type SessionStatus } from '../../../core/domain/session-status';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { ToolsPage } from '../../settings/pages/ToolsPage';
import { AgentListTab } from './AgentListTab';
import { WorkTab } from './WorkTab';
import { JobsTab } from './JobsTab';
import { Inspector } from '../widgets';
import { usePicked } from '../inspector-host';
import { SessionsTabLines } from '../../../core/domain/agent-lines';
import { BrandLogo, Button, EmptyState, Panel, Row, Section, StatusWord, type Tone } from '../../kit';

/** The order the groups are read in: what needs the person, then what runs, then what is done. */
const GROUPS: readonly { title: string; holds: readonly SessionStatus[] }[] = [
  { title: SessionsTabLines.needsYou, holds: ['needs-you', 'waiting-on-you', 'paused'] },
  { title: SessionsTabLines.running, holds: ['working', 'thinking'] },
  { title: SessionsTabLines.idle, holds: ['quiet'] },
  { title: SessionsTabLines.finished, holds: ['ended'] },
];

/** An agent's logo at the head of its row, and larger at the head of its details. */
const ROW_LOGO = 28;
const DETAIL_LOGO = 36;

export function toneOf(status: SessionStatus): Tone {
  if (status === 'paused') return 'bad';
  if (status === 'needs-you' || status === 'waiting-on-you') return 'attention';
  if (status === 'working' || status === 'thinking') return 'good';
  return 'quiet';
}

export function AgentsPage({ parts, tab, width }: { parts: SettingsParts; tab: string | undefined; width: WidthClass }) {
  if (tab === 'computer') return <ToolsPage parts={parts} />;
  if (tab === 'list') return <AgentListTab parts={parts} />;
  if (tab === 'work') return <WorkTab parts={parts} />;
  if (tab === 'profiles') return <JobsTab parts={parts} />;
  return <SessionsTab parts={parts} width={width} />;
}

function SessionsTab({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { sessions, host } = parts;
  useObserved(sessions);
  useEffect(() => {
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [chosen, choose] = usePicked();
  const cards = sessions.state.cards;
  const picked = cards.find((card) => card.sessionId === chosen);

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
                  <SessionRow key={card.sessionId} card={card} chosen={card.sessionId === chosen} pick={() => choose(card.sessionId)} />
                ))}
              </Panel>
            </Section>
          );
        })}
      </div>
      {picked !== undefined && (
        <Inspector title={picked.agentName} width={width} close={() => choose(undefined)} item={picked.sessionId}>
          <SessionDetail card={picked} open={() => host.openLive?.(picked.sessionId)} />
        </Inspector>
      )}
    </div>
  );
}

function SessionRow({ card, chosen, pick }: { card: SessionCard; chosen: boolean; pick: () => void }) {
  const status = cardStatus(card);
  return (
    <Row
      chosen={chosen}
      leading={<BrandLogo agent={card.agent} name={card.agentName} size={ROW_LOGO} />}
      title={cardTitle(card)}
      caption={[card.agentName, repositoryName(card.repository), ago(card.lastActive, Date.now())].filter((part) => part !== undefined).join(' · ')}
      trailing={<StatusWord tone={toneOf(status)}>{statusLabel(status)}</StatusWord>}
      onClick={pick}
    />
  );
}

function SessionDetail({ card, open }: { card: SessionCard; open: () => void }) {
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
      <Button kind="primary" onClick={open}>
        {SessionsTabLines.openLive}
      </Button>
    </div>
  );
}
