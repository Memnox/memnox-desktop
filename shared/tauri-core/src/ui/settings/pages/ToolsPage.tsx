import { Brain, Copy, RotateCw, Terminal, TriangleAlert } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { agentStatusWord } from '../../../core/application/tools';
import { EMBEDDING_COMMAND, MEANING_SEARCH_LINE, MEANING_SEARCH_TITLE } from '../../../core/domain/memory-lines';
import { AgentMark } from '../../kit/logos';
import { SettingsCard, SettingsDivider, SettingsRow, SettingsSection } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { Button } from '../../kit';
import { ToolsPageLines } from '../../../core/domain/tools-page-lines';
import { AgentHomesLines } from '../../../core/domain/agent-homes';
import { AgentHomesSetup } from './AgentHomesSetup';
import { CONNECTION_PAGE, RuntimeAwayLines } from '../../../core/domain/runtime-away';

/** A 7 dot after a tool: ready in the success colour, needing the person in the warm one. */
function StatusDot({ ready }: { ready: boolean }) {
  return <span className={`size-settings-tool-dot shrink-0 rounded-full ${ready ? 'bg-success' : 'bg-warm'}`} aria-label={ready ? ToolsPageLines.ready : ToolsPageLines.needsYou} />;
}

/**
 * On this computer, as the Mac's `ToolsPage`: the agents here, where they run, and search by meaning. The person's own
 * apps are their own page, Your apps, as on the Mac.
 */
export function ToolsPage({ parts }: { parts: SettingsParts }) {
  const { tools, host } = parts;
  useObserved(tools);
  useEffect(() => void tools.refresh(), []);
  const { agents, reading, agentsNote } = tools.state;
  return (
    <>
      <SettingsCard title={ToolsPageLines.agents}>
        {agents.length === 0 && agentsNote !== undefined && !reading ? (
          // With the service away, no agent could be read, which is not the same as none being installed.
          <SettingsRow icon={TriangleAlert} title={agentsNote} caption={RuntimeAwayLines.agentsCaption}>
            <Button onClick={() => host.openSettings(CONNECTION_PAGE)}>{RuntimeAwayLines.openConnection}</Button>
          </SettingsRow>
        ) : agents.length === 0 ? (
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
      {/* The same checklist as the first run, for an app installed since or a step skipped then. */}
      <SettingsSection title={AgentHomesLines.section}>
        <AgentHomesSetup homes={parts.homes} platform={parts.host.platform} />
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
