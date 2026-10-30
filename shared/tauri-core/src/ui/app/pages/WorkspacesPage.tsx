import type { ProjectView } from '@memnox/core/wire';
import { FolderGit2, FolderOpen } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { folderProblem } from '../../../core/domain/launch-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { counted, foldersToOpen, projectStanding, sharedBy } from '../../../core/domain/project-lines';
import { workspacesFrom, type SeenWorkspace } from '../../../core/domain/workspaces';
import { ago } from '../../../core/domain/session-text';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { DiscoverPage } from './DiscoverPage';
import { MemoryPage } from './MemoryPage';
import { ProfilesPage } from './ProfilesPage';
import { OrganizationBadge, ProjectInspector, projectNote } from './ProjectInspector';
import { SkillsPage } from './SkillsPage';
import { CardGrid, EmptyState, Inspector, ReadFailed, ScopeChip, Section, StatTile, StatusWord } from '../widgets';
import { projectScope } from '../../../core/domain/scope-lines';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';
import { projectsShown, withCurrent } from '../../../core/domain/shell-lines';

/**
 * Projects as the runtime keeps them, with what each gives the agents opened in it. A runtime too old to
 * answer `projects` still shows every repository a session ran in, with who worked there.
 */
export function WorkspacesPage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  const { support } = parts;
  useObserved(support);
  if (tab === 'skills' || tab === 'assigned') return <SkillsPage parts={parts} tab={tab} width={width} />;
  if (tab === 'memory') return <MemoryPage parts={parts} width={width} />;
  if (tab === 'discover') return <DiscoverPage parts={parts} width={width} />;
  if (tab === 'profiles') return <ProfilesPage parts={parts} />;
  if (support.supports('projects') === true) return <ProjectsTab parts={parts} width={width} />;
  return <SeenTab parts={parts} width={width} go={go} />;
}

function ProjectsTab({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { projects, sessions } = parts;
  useObserved(projects, sessions);
  useEffect(() => {
    void projects.refresh();
    // The folders the sessions ran in are offered as quick picks to open.
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [chosen, choose] = usePicked();
  const [opening, setOpening] = useState(false);
  const [note, setNote] = useState<string | undefined>(undefined);
  const { project } = useShellChoices();
  const all = projects.projects;
  if (all === undefined) return projects.unreadable ? <ReadFailed what="the projects" retry={() => void projects.refresh()} /> : null;
  const list = projectsShown(all, project);
  const picked = list.find((each) => each.id === chosen);
  // The current project is offered first, so opening it again to reapply its setup is one press.
  const folders = withCurrent(
    foldersToOpen(
      workspacesFrom(sessions.state.cards, Date.now()).map((each) => ({ path: each.path, name: each.name })),
      all,
    ),
    project,
  );
  const open = (
    <KitButton icon={FolderOpen} onClick={() => setOpening(!opening)} aria-expanded={opening}>
      Open a folder
    </KitButton>
  );
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <div className="flex items-center justify-between gap-3">
          <p className="text-footnote text-muted">{counted(list.length, 'project', 'projects')}, most recently active first.</p>
          {open}
        </div>
        {opening && (
          <OpenFolderForm
            folders={folders}
            busy={projects.busy !== undefined}
            cancel={() => setOpening(false)}
            open={(folder) =>
              void projects.open(folder).then((outcome) => {
                setNote(projectNote(outcome, parts.words.keyTitle));
                if (outcome.kind !== 'failed') setOpening(false);
              })
            }
          />
        )}
        {note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>}
        {list.length === 0 ? (
          <EmptyState icon={FolderGit2} title="No projects yet" body="Open a folder to make it a project, or start an agent in a repository and it appears here with every agent that worked there." />
        ) : (
          <CardGrid>
            {list.map((each) => (
              <ProjectCard key={each.id} project={each} chosen={each.id === chosen} pick={() => choose(each.id)} />
            ))}
          </CardGrid>
        )}
      </div>
      {picked !== undefined && (
        <Inspector title={picked.name} width={width} close={() => choose(undefined)} item={picked.id}>
          <ProjectInspector key={picked.id} parts={parts} project={picked} said={setNote} />
        </Inspector>
      )}
    </div>
  );
}

function ProjectCard({ project, chosen, pick }: { project: ProjectView; chosen: boolean; pick: () => void }) {
  const standing = projectStanding(project);
  const active = ago(project.lastActive, Date.now());
  return (
    <button
      type="button"
      onClick={pick}
      aria-pressed={chosen}
      className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-xl border bg-card p-4 text-left transition-colors hover:bg-hover ${chosen ? 'border-primary' : 'border-panel-edge'}`}
    >
      <div className="flex items-center gap-2">
        <FolderGit2 size={16} className="text-muted" aria-hidden />
        <span className="min-w-0 flex-1 truncate text-body font-semibold text-foreground">{project.name}</span>
        {sharedBy(project) === undefined ? <StatusWord tone={standing.tone}>{standing.word}</StatusWord> : <OrganizationBadge />}
      </div>
      <span className="flex items-center gap-2">
        <ScopeChip scope={projectScope(project)} />
        <span className="min-w-0 truncate font-mono text-micro text-muted">{project.path}</span>
      </span>
      <span className="text-footnote text-muted">{`${counted(project.skills.length, 'skill', 'skills')} · ${counted(project.servers.length, 'server', 'servers')} · ${counted(project.openMissions.length, 'open mission', 'open missions')}`}</span>
      <div className="flex items-center justify-between gap-2">
        <span className="flex -space-x-1.5">
          {project.agents.map((kind) => (
            <BrandLogo key={kind} agent={kind} name={agentLabel(kind)} size={20} className="ring-2 ring-card" />
          ))}
        </span>
        <span className="text-footnote text-muted">{active === undefined ? '' : `Active ${active}`}</span>
      </div>
    </button>
  );
}

/** The folder to take in as a project: typed whole, or one the sessions ran in that is not a project yet. */
function OpenFolderForm({ folders, busy, cancel, open }: { folders: readonly { path: string; name: string }[]; busy: boolean; cancel: () => void; open: (folder: string) => void }) {
  const [folder, setFolder] = useState(folders[0]?.path ?? '');
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const go = () => {
    const wrong = folderProblem(folder);
    setProblem(wrong);
    if (wrong === undefined) open(folder);
  };
  return (
    <div className="flex flex-col gap-2 rounded-xl border border-panel-edge bg-card p-4">
      <label className="flex flex-col gap-1.5">
        <span className="text-footnote font-medium text-muted">The folder, from the top of the drive</span>
        <input
          className="h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 font-mono text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary"
          value={folder}
          placeholder="/home/you/code/project"
          onChange={(event) => setFolder(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && go()}
          autoFocus
        />
      </label>
      {folders.length > 0 && (
        <div className="flex flex-wrap gap-1.5" aria-label="Folders your agents worked in">
          {folders.map((each) => (
            <button
              key={each.path}
              type="button"
              title={each.path}
              aria-pressed={folder === each.path}
              onClick={() => setFolder(each.path)}
              className={`mx-focus cursor-pointer rounded-full border px-2.5 py-1 text-footnote ${folder === each.path ? 'border-primary text-foreground' : 'border-panel-edge text-muted hover:bg-hover'}`}
            >
              {each.name}
            </button>
          ))}
        </div>
      )}
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
      <p className="text-footnote text-muted">Opening hands its instructions to its agents at once. Whatever widens an agent waits for your signature on the island.</p>
      <div className="flex gap-2">
        <KitButton kind="primary" icon={FolderOpen} disabled={busy} onClick={go}>
          {busy ? 'Opening' : 'Open'}
        </KitButton>
        <KitButton onClick={cancel}>Cancel</KitButton>
      </div>
    </div>
  );
}

/** Repositories as the sessions met them, for a runtime that does not answer `projects`. */
function SeenTab({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { sessions } = parts;
  useObserved(sessions);
  useEffect(() => {
    sessions.start();
    return () => sessions.stop();
  }, []);
  const [chosen, choose] = usePicked();
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
        <Inspector title={picked.name} width={width} close={() => choose(undefined)} item={picked.path}>
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
