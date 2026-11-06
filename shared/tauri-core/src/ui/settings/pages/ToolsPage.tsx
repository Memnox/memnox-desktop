import { Brain, Copy, RotateCw, SquareTerminal, Terminal } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { agentStatusWord } from '../../../core/application/tools';
import { EMBEDDING_COMMAND, MEANING_SEARCH_LINE, MEANING_SEARCH_TITLE } from '../../../core/domain/memory-lines';
import { AgentMark } from '../../kit/logos';
import { KitButton, SettingsCard, SettingsDivider, SettingsRow, SettingsSection } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

/** A 7 dot after a tool: ready in the success colour, needing the person in the warm one. */
function StatusDot({ ready }: { ready: boolean }) {
  return <span className={`size-[7px] shrink-0 rounded-full ${ready ? 'bg-success' : 'bg-warm'}`} aria-label={ready ? 'Ready' : 'Needs you'} />;
}

/**
 * On this computer, as the Mac's `ToolsPage`: the agents here, where they run, and search by meaning. The person's own
 * apps are their own page, Your apps, as on the Mac.
 */
export function ToolsPage({ parts }: { parts: SettingsParts }) {
  const { tools, steps } = parts;
  useObserved(tools, steps);
  useEffect(() => {
    void tools.refresh();
    void steps.refresh();
  }, []);
  const { agents, reading } = tools.state;
  const editor = steps.editor;
  return (
    <>
      <SettingsCard title="Agents">
        {agents.length === 0 ? (
          <SettingsRow icon={Terminal} title={reading ? 'Looking for agents' : 'No agents found'} caption="Install Claude Code, Codex or Cursor and Memnox finds it." />
        ) : (
          agents.map((agent, index) => (
            <Fragment key={agent.kind}>
              {index > 0 && <SettingsDivider />}
              <SettingsRow tile={<AgentMark agent={agent.kind} name={agent.label} />} title={agent.label} caption={<span className="text-micro">{agentStatusWord(agent)}</span>}>
                <StatusDot ready={agent.works !== false} />
              </SettingsRow>
            </Fragment>
          ))
        )}
      </SettingsCard>
      {/* The same check as the first run, for an editor installed since; Windows and Linux find a session's tab without asking. */}
      <SettingsSection title="Where your agents run">
        <SettingsCard>
          {editor.shown ? (
            <SettingsRow icon={SquareTerminal} title="Memnox in your editor" caption={editor.detail}>
              {editor.state.kind !== 'done' && <KitButton onClick={() => void steps.readPermissions()}>Check again</KitButton>}
              <StatusDot ready={editor.state.kind === 'done'} />
            </SettingsRow>
          ) : (
            <SettingsRow icon={SquareTerminal} title="No editor found" caption="Memnox works with VS Code, Cursor and Windsurf, and finds the terminal each session runs in on its own." />
          )}
        </SettingsCard>
      </SettingsSection>
      <SettingsCard title="Memory">
        <SettingsRow
          icon={Brain}
          title={MEANING_SEARCH_TITLE}
          caption={
            <>
              {MEANING_SEARCH_LINE} <code className="font-mono text-foreground">{EMBEDDING_COMMAND}</code>
            </>
          }
        >
          <KitButton icon={Copy} onClick={() => void parts.host.copy(EMBEDDING_COMMAND)}>
            Copy
          </KitButton>
        </SettingsRow>
      </SettingsCard>
      <div className="flex justify-end">
        <KitButton icon={RotateCw} onClick={() => void tools.refresh()}>
          Check again
        </KitButton>
      </div>
    </>
  );
}
