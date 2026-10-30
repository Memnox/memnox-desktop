import type { SessionCard } from '@memnox/core/wire';
import { Bot } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { WidthClass } from '../../../core/domain/destinations';
import { ago, cardStatus, cardTitle, repositoryName } from '../../../core/domain/session-text';
import { statusLabel, type SessionStatus } from '../../../core/domain/session-status';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { ToolsPage } from '../../settings/pages/ToolsPage';
import { AgentListTab } from './AgentListTab';
import { EmptyState, Inspector, Panel, Row, Section, StatusWord, type Tone } from '../widgets';
import { usePicked } from '../inspector-host';

/** The order the groups are read in: what needs the person, then what runs, then what is done. */
const GROUPS: readonly { title: string; holds: readonly SessionStatus[] }[] = [
  { title: 'Needs you', holds: ['needs-you', 'waiting-on-you', 'paused'] },
  { title: 'Running', holds: ['working', 'thinking'] },
  { title: 'Idle', holds: ['quiet'] },
  { title: 'Finished', holds: ['ended'] },
];

export function toneOf(status: SessionStatus): Tone {
  if (status === 'paused') return 'bad';
  if (status === 'needs-you' || status === 'waiting-on-you') return 'attention';
  if (status === 'working' || status === 'thinking') return 'good';
  return 'quiet';
}

export function AgentsPage({ parts, tab, width }: { parts: SettingsParts; tab: string | undefined; width: WidthClass }) {
  if (tab === 'computer') return <ToolsPage parts={parts} />;
  if (tab === 'list') return <AgentListTab parts={parts} />;
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
    return <EmptyState icon={Bot} title="No sessions yet" body="When an agent on this computer starts working, its session shows here with what it is doing and what it touched." />;
  }
  return (
    <div className="flex min-h-0 gap-0">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        {GROUPS.map((group) => {
          const held = cards.filter((card) => group.holds.includes(cardStatus(card)));
          if (held.length === 0) return null;
          return (
            <Section key={group.title} title={`${group.title} · ${held.length}`}>
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
      leading={<BrandLogo agent={card.agent} name={card.agentName} size={28} />}
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
    ['Status', statusLabel(status)],
    ['Working on', card.focus ?? card.task],
    ['Repository', repositoryName(card.repository)],
    ['Running in', card.where ?? card.runningIn],
    ['Started', ago(card.startedAt, Date.now())],
    ['Last active', ago(card.lastActive, Date.now())],
    ['Actions', card.actions === undefined ? undefined : String(card.actions)],
  ];
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-3">
        <BrandLogo agent={card.agent} name={card.agentName} size={36} />
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
      <KitButton kind="primary" onClick={open}>
        Open its live window
      </KitButton>
    </div>
  );
}
