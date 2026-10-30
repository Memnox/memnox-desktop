import { FolderGit2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { workspacesFrom, type SeenWorkspace } from '../../../core/domain/workspaces';
import { ago } from '../../../core/domain/session-text';
import { BrandLogo } from '../../kit/logos';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { CardGrid, EmptyState, Inspector, Section, StatTile } from '../widgets';

/**
 * Projects as the agents met them: every repository a session ran in, with who worked there. A workspace
 * that also carries its own skills, servers and rules joins this once the runtime keeps them per project.
 */
export function WorkspacesPage({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { sessions } = parts;
  useObserved(sessions);
  useEffect(() => {
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [chosen, choose] = useState<string | undefined>(undefined);
  const workspaces = workspacesFrom(sessions.state.cards, Date.now());
  const picked = workspaces.find((each) => each.path === chosen);

  if (workspaces.length === 0) {
    return <EmptyState icon={FolderGit2} title="No workspaces yet" body="A workspace appears once an agent works in a repository on this computer, with every agent that has worked there." />;
  }
  return (
    <div className="flex min-h-0">
      <div className="min-w-0 flex-1">
        <CardGrid>
          {workspaces.map((each) => (
            <WorkspaceCard key={each.path} workspace={each} chosen={each.path === chosen} pick={() => choose(each.path)} />
          ))}
        </CardGrid>
      </div>
      {picked !== undefined && (
        <Inspector title={picked.name} width={width} close={() => choose(undefined)}>
          <WorkspaceOverview workspace={picked} go={go} />
        </Inspector>
      )}
    </div>
  );
}

function WorkspaceCard({ workspace, chosen, pick }: { workspace: SeenWorkspace; chosen: boolean; pick: () => void }) {
  return (
    <button
      type="button"
      onClick={pick}
      aria-pressed={chosen}
      className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-xl border bg-card p-4 text-left transition-colors hover:bg-hover ${chosen ? 'border-primary' : 'border-panel-edge'}`}
    >
      <div className="flex items-center gap-2">
        <FolderGit2 size={16} className="text-muted" aria-hidden />
        <span className="truncate text-body font-semibold text-foreground">{workspace.name}</span>
      </div>
      <span className="truncate font-mono text-micro text-muted">{workspace.path}</span>
      <div className="flex items-center justify-between gap-2">
        <span className="flex -space-x-1.5">
          {workspace.agents.map((agent) => (
            <BrandLogo key={agent.kind} agent={agent.kind} name={agent.name} size={20} className="ring-2 ring-card" />
          ))}
        </span>
        <span className="text-footnote text-muted">{workspace.lastActive === undefined ? '' : `Active ${workspace.lastActive}`}</span>
      </div>
    </button>
  );
}

function WorkspaceOverview({ workspace, go }: { workspace: SeenWorkspace; go: (route: Route) => void }) {
  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-2.5">
        <StatTile value={workspace.agents.length} label={workspace.agents.length === 1 ? 'Agent' : 'Agents'} />
        <StatTile value={workspace.sessions} label={workspace.sessions === 1 ? 'Session' : 'Sessions'} />
      </div>
      <Section title="Agents that worked here">
        <div className="flex flex-col gap-2">
          {workspace.agents.map((agent) => (
            <div key={agent.kind} className="flex items-center gap-2.5">
              <BrandLogo agent={agent.kind} name={agent.name} size={24} />
              <span className="text-body text-foreground">{agent.name}</span>
            </div>
          ))}
        </div>
      </Section>
      <GoLink onClick={() => go({ destination: 'agents', tab: 'sessions' })}>Its sessions</GoLink>
      <p className="text-footnote text-muted">{`Last active ${ago(workspace.lastActiveAt, Date.now()) ?? 'a while ago'}.`}</p>
    </div>
  );
}
