import { Link, RotateCw, Terminal, UserRoundX } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { agentStatusWord, connectionStatusWord } from '../../../core/application/tools';
import { toolkitName } from '../../../core/domain/tool-brand';
import { AgentMark, ToolMark } from '../../kit/logos';
import { KitButton, SettingsCard, SettingsDivider, SettingsRow } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

/** A 7 dot after a tool: ready in the success colour, needing the person in the warm one. */
function StatusDot({ ready }: { ready: boolean }) {
  return <span className={`size-[7px] shrink-0 rounded-full ${ready ? 'bg-success' : 'bg-warm'}`} aria-label={ready ? 'Ready' : 'Needs you'} />;
}

/** The Connected tools page, as the Mac's `ToolsPage`: the agents on this computer, then the person's own apps. */
export function ToolsPage({ parts }: { parts: SettingsParts }) {
  const { tools } = parts;
  useObserved(tools);
  useEffect(() => void tools.refresh(), []);
  const { agents, connections, connectionsNote, reading } = tools.state;
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
      <SettingsCard title="Apps">
        {connectionsNote !== undefined && (
          <>
            <SettingsRow icon={UserRoundX} tint="var(--mx-warm)" title="Your apps are not showing" caption={connectionsNote} />
            {connections.length > 0 && <SettingsDivider />}
          </>
        )}
        {connections.length === 0 && connectionsNote === undefined ? (
          <SettingsRow icon={Link} title={reading ? 'Reading your apps' : 'No apps connected yet'} caption="Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you." />
        ) : (
          connections.map((connection, index) => (
            <Fragment key={connection.toolkit}>
              {index > 0 && <SettingsDivider />}
              <SettingsRow tile={<ToolMark toolkit={connection.toolkit} size={26} />} title={toolkitName(connection.toolkit)} caption={connectionStatusWord(connection)}>
                <StatusDot ready={connection.connected} />
              </SettingsRow>
            </Fragment>
          ))
        )}
      </SettingsCard>
      <div className="flex justify-end">
        <KitButton icon={RotateCw} onClick={() => void tools.refresh()}>
          Check again
        </KitButton>
      </div>
    </>
  );
}
