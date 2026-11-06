import { Brain, Copy, RotateCw, SquareTerminal, Terminal } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { agentStatusWord } from '../../../core/application/tools';
import { EMBEDDING_COMMAND, MEANING_SEARCH_LINE, MEANING_SEARCH_TITLE } from '../../../core/domain/memory-lines';
import { AgentMark } from '../../kit/logos';
import { SettingsCard, SettingsDivider, SettingsRow, SettingsSection } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { Button } from '../../kit';
import { ToolsPageLines } from '../../../core/domain/tools-page-lines';

/** A 7 dot after a tool: ready in the success colour, needing the person in the warm one. */
function StatusDot({ ready }: { ready: boolean }) {
  return <span className={`size-[7px] shrink-0 rounded-full ${ready ? 'bg-success' : 'bg-warm'}`} aria-label={ready ? ToolsPageLines.ready : ToolsPageLines.needsYou} />;
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
      <SettingsCard title={ToolsPageLines.agents}>
        {agents.length === 0 ? (
          <SettingsRow icon={Terminal} title={reading ? ToolsPageLines.looking : ToolsPageLines.noAgents} caption={ToolsPageLines.installHint} />
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
      <SettingsSection title={ToolsPageLines.whereRun}>
        <SettingsCard>
          {editor.shown ? (
            <SettingsRow icon={SquareTerminal} title={ToolsPageLines.editor} caption={editor.detail}>
              {editor.state.kind !== 'done' && <Button onClick={() => void steps.readPermissions()}>{ToolsPageLines.checkAgain}</Button>}
              <StatusDot ready={editor.state.kind === 'done'} />
            </SettingsRow>
          ) : (
            <SettingsRow icon={SquareTerminal} title={ToolsPageLines.noEditor} caption={ToolsPageLines.editorHint} />
          )}
        </SettingsCard>
      </SettingsSection>
      <SettingsCard title={ToolsPageLines.memory}>
        <SettingsRow
          icon={Brain}
          title={MEANING_SEARCH_TITLE}
          caption={
            <>
              {MEANING_SEARCH_LINE} <code className="font-mono text-foreground">{EMBEDDING_COMMAND}</code>
            </>
          }
        >
          <Button icon={Copy} onClick={() => void parts.host.copy(EMBEDDING_COMMAND)}>
            {ToolsPageLines.copy}
          </Button>
        </SettingsRow>
      </SettingsCard>
      <div className="flex justify-end">
        <Button icon={RotateCw} onClick={() => void tools.refresh()}>
          {ToolsPageLines.checkAgain}
        </Button>
      </div>
    </>
  );
}
