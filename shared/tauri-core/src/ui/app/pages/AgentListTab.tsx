import type { AgentView } from '@memnox/core/wire';
import { Bot, Pause, Play } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { StudioOutcome } from '../../../core/application/studio';
import { ago } from '../../../core/domain/session-text';
import { EFFECT_WORDS, effectTone, isEffect } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { CardGrid, EmptyState, ReadFailed, StatusWord, type Tone } from '../widgets';

const STATUS: Record<AgentView['status'], { word: string; tone: Tone }> = {
  protected: { word: 'Protected', tone: 'good' },
  unprotected: { word: 'Not protected', tone: 'attention' },
  dormant: { word: 'Dormant', tone: 'quiet' },
  paused: { word: 'Paused', tone: 'bad' },
};

/** Every agent on this computer as the runtime sees it, the ones needing a decision first. */
export function AgentListTab({ parts }: { parts: SettingsParts }) {
  const { agents, home, words } = parts;
  useObserved(agents, home);
  useEffect(() => {
    void agents.refresh();
  }, []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const said = (outcome: StudioOutcome) =>
    setNote(outcome.kind === 'proposed' ? `Waiting for you on the island: confirm it with ${words.keyTitle}.` : outcome.kind === 'failed' ? outcome.why : outcome.note);

  const list = agents.agents;
  if (list === undefined) return agents.unreadable ? <ReadFailed what="the agents" retry={() => void agents.refresh()} /> : null;
  if (list.length === 0) return <EmptyState icon={Bot} title="No agents found yet" body="Install Claude Code, Codex, Cursor or another agent and it appears here." />;
  const order: AgentView['status'][] = ['paused', 'unprotected', 'protected', 'dormant'];
  const sorted = [...list].sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status));
  return (
    <>
      {note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>}
      <CardGrid>
        {sorted.map((agent) => (
          <article key={agent.kind} className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
            <header className="flex items-center gap-2.5">
              <BrandLogo agent={agent.kind} name={agent.name} size={30} />
              <div className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-headline font-semibold text-foreground">{agent.name}</span>
                <StatusWord tone={STATUS[agent.status].tone}>{STATUS[agent.status].word}</StatusWord>
              </div>
            </header>
            <p className="text-footnote text-muted">
              {`${agent.sessions.running} running, ${agent.sessions.idle} idle, ${agent.sessions.finished} finished · Today ${agent.today.actions} actions, ${agent.today.asked} asked, ${agent.today.refused} refused`}
            </p>
            {agent.mcpServers.length > 0 && <p className="truncate text-footnote text-muted">{`Servers: ${agent.mcpServers.join(', ')}`}</p>}
            {agent.recent.length > 0 && (
              <ul className="flex flex-col gap-1">
                {agent.recent.map((action) => (
                  <li key={action.id} className="flex items-center gap-2 text-footnote">
                    <span className="min-w-0 flex-1 truncate font-mono text-foreground">{action.target === undefined ? action.operation : `${action.operation} ${action.target}`}</span>
                    <span className="text-muted">{ago(action.at, Date.now())}</span>
                    <StatusWord tone={effectTone(action.effect)}>{isEffect(action.effect) ? EFFECT_WORDS[action.effect].title : action.effect}</StatusWord>
                  </li>
                ))}
              </ul>
            )}
            <footer className="flex flex-wrap gap-2 pt-1">
              {agent.status === 'paused' ? (
                <KitButton icon={Play} disabled={agents.busy === agent.kind} onClick={() => void agents.resume(agent.kind).then(said)}>
                  Resume
                </KitButton>
              ) : (
                <KitButton icon={Pause} disabled={agents.busy === agent.kind} onClick={() => void agents.pause(agent.kind).then(said)}>
                  Pause
                </KitButton>
              )}
              {agent.status === 'unprotected' && (
                <KitButton kind="primary" disabled={home.protecting} onClick={() => void home.protect()}>
                  Protect
                </KitButton>
              )}
            </footer>
          </article>
        ))}
      </CardGrid>
    </>
  );
}
