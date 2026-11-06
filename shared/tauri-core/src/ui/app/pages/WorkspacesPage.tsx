import type { ProjectView } from '@memnox/core/wire';
import { ExternalLink, Folder, FolderGit2, FolderOpen, MoreHorizontal, Pencil, Plus, Search } from 'lucide-react';
import { useEffect, useState } from 'react';
import { projectRoute, type Route, type WidthClass } from '../../../core/domain/destinations';
import { folderProblem } from '../../../core/domain/launch-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { counted, foldersToOpen, projectCard, projectStanding, sharedBy } from '../../../core/domain/project-lines';
import {
  ADD_TITLE,
  CHOOSE_TITLE,
  EMPTY_LINE,
  EMPTY_TITLE,
  matching,
  pulse,
  recent,
  SEARCH_FROM,
  SEARCH_PROMPT,
  SUGGESTIONS_NOTE,
  SUGGESTIONS_TITLE,
  waitingLine,
  workingLine,
  type ProjectPulse,
} from '../../../core/domain/project-context';
import { workspacesFrom, type SeenWorkspace } from '../../../core/domain/workspaces';
import { ago } from '../../../core/domain/session-text';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { DiscoverPage } from './DiscoverPage';
import { MemoryPage, MemorySourcesPage } from './MemoryPage';
import { OrganizationBadge, projectNote } from './ProjectInspector';
import { cloudProjectLink, editableHere, OPEN_IN_CLOUD, renamedDraft, renameProblem } from '../../../core/domain/project-sidebar';
import { openOrCopy } from '../../settings/host';
import { SkillsPage } from './SkillsPage';
import { CardGrid, EmptyState, Inspector, ReadFailed, ScopeChip, Section, StatTile, StatusWord } from '../widgets';
import { projectScope } from '../../../core/domain/scope-lines';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';

/**
 * Projects as the runtime keeps them, with what each gives the agents opened in it. A runtime too old to
 * answer `projects` still shows every repository a session ran in, with who worked there.
 */
export function WorkspacesPage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  const { support } = parts;
  useObserved(support);
  if (tab === 'skills' || tab === 'assigned') return <SkillsPage parts={parts} tab={tab} width={width} />;
  // One Memory page, opening on the map, so an old Map link lands here too.
  if (tab === 'memory' || tab === 'map') return <MemoryPage parts={parts} width={width} go={go} />;
  // Where memory is read from, under Inputs beside the connectors, as Memnox Cloud places its sources.
  if (tab === 'sources') return <MemorySourcesPage parts={parts} />;
  if (tab === 'discover') return <DiscoverPage parts={parts} width={width} />;
  if (support.supports('projects') === true) return <ProjectsTab parts={parts} go={go} />;
  return <SeenTab parts={parts} width={width} go={go} />;
}

/** How long the list waits before opening the live feed of held calls again after the daemon went away. */
const HELD_RECONNECT_MS = 2_000;

/**
 * The project list, modelled on Memnox Cloud's projects page: a card each, most recently active first, saying who works
 * there now and what waits on the person there, with a search once there are many. Adding one is a press on a folder the
 * agents already worked in, or on Choose a folder. Opening one swaps the sidebar for that project's own pages.
 */
function ProjectsTab({ parts, go }: { parts: SettingsParts; go: (route: Route) => void }) {
  const { projects, sessions, calls } = parts;
  useObserved(projects, sessions, calls);
  useEffect(() => {
    void projects.refresh();
    // The folders the sessions ran in are offered as projects to add.
    sessions.start();
    // What waits on the person is read live, so each card says what waits there.
    let watching = true;
    const feed = async () => {
      while (watching) {
        await calls.watch();
        if (watching) await new Promise((resolve) => setTimeout(resolve, HELD_RECONNECT_MS));
      }
    };
    void feed();
    return () => {
      watching = false;
      sessions.stop();
    };
  }, []);
  const [opening, setOpening] = useState(false);
  const [query, setQuery] = useState('');
  const [note, setNote] = useState<string | undefined>(undefined);
  const { chooseProject } = useShellChoices();
  const all = projects.projects;
  if (all === undefined) return projects.unreadable ? <ReadFailed what="the projects" retry={() => void projects.refresh()} /> : null;
  // Every project shows here: the list is where a person picks one, so nothing narrows it.
  const list = matching(recent(all), query);
  const folders = foldersToOpen(
    workspacesFrom(sessions.state.cards, Date.now()).map((each) => ({ path: each.path, name: each.name })),
    all,
  );
  const places = calls.state.waiting.entries.map((entry) => entry.card.place);
  const busy = projects.busy !== undefined;
  const add = (folder: string) =>
    void projects.open(folder).then((outcome) => {
      setNote(projectNote(outcome, parts.words.keyTitle));
      if (outcome.kind !== 'failed') setOpening(false);
    });
  const open = (id: string) => {
    chooseProject(id);
    go(projectRoute(id));
  };
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-footnote text-muted">{all.length === 0 ? EMPTY_TITLE : `${counted(all.length, 'project', 'projects')}, most recently active first.`}</p>
        <KitButton kind="primary" icon={FolderOpen} onClick={() => setOpening(!opening)} aria-expanded={opening}>
          {CHOOSE_TITLE}
        </KitButton>
      </div>
      {opening && <OpenFolderForm busy={busy} cancel={() => setOpening(false)} open={add} />}
      {note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>}
      {folders.length > 0 && <Suggestions folders={folders} busy={busy} add={add} />}
      {all.length === 0 ? (
        <EmptyState icon={Folder} title={EMPTY_TITLE} body={EMPTY_LINE} action={<KitButton kind="primary" icon={FolderOpen} onClick={() => setOpening(true)}>{CHOOSE_TITLE}</KitButton>} />
      ) : (
        <>
          {all.length >= SEARCH_FROM && (
            <label className="flex max-w-sm items-center gap-2 rounded-lg border border-field-edge bg-field px-3">
              <Search size={14} className="text-muted" aria-hidden />
              <input className="h-9 min-w-0 flex-1 bg-transparent text-body-sm text-foreground outline-none placeholder:text-faint" value={query} placeholder={SEARCH_PROMPT} aria-label={SEARCH_PROMPT} onChange={(event) => setQuery(event.target.value)} />
            </label>
          )}
          {list.length === 0 ? (
            <EmptyState icon={Search} title="No project matches that" body="Try another word, or clear the search." />
          ) : (
            <CardGrid>
              {list.map((each) => (
                <ProjectCard key={each.id} parts={parts} project={each} pulse={pulse(each, sessions.state.cards, places, Date.now())} pick={() => open(each.id)} said={setNote} />
              ))}
            </CardGrid>
          )}
        </>
      )}
    </div>
  );
}

/** The folders the agents already worked in that are not projects yet, each made one with a single press. */
function Suggestions({ folders, busy, add }: { folders: readonly { path: string; name: string }[]; busy: boolean; add: (folder: string) => void }) {
  return (
    <section aria-label={SUGGESTIONS_TITLE} className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
      <div className="flex flex-col gap-0.5">
        <h2 className="text-body-sm font-semibold text-foreground">{SUGGESTIONS_TITLE}</h2>
        <p className="text-footnote text-muted">{SUGGESTIONS_NOTE}</p>
      </div>
      <ul className="flex flex-col divide-y divide-panel-edge">
        {folders.map((each) => (
          <li key={each.path} className="flex items-center gap-3 py-2">
            <FolderGit2 size={15} className="shrink-0 text-muted" aria-hidden />
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate text-body-sm font-medium text-foreground">{each.name}</span>
              <span className="truncate font-mono text-micro text-muted" title={each.path}>
                {each.path}
              </span>
            </span>
            <KitButton icon={Plus} disabled={busy} onClick={() => add(each.path)} aria-label={`Add ${each.name} as a project`}>
              {ADD_TITLE}
            </KitButton>
          </li>
        ))}
      </ul>
    </section>
  );
}

/**
 * A project as the console's card: its name, what it is about, who worked there, and whether it keeps memory. A press
 * opens it; its menu renames it or shows its folder, and an organization's project opens in Memnox Cloud instead,
 * since this computer cannot change it. The daemon has no way to remove a project, so the menu offers none.
 */
function ProjectCard({ parts, project, pulse, pick, said }: { parts: SettingsParts; project: ProjectView; pulse: ProjectPulse; pick: () => void; said: (note: string) => void }) {
  const { projects, words } = parts;
  const standing = projectStanding(project);
  const card = projectCard(project);
  const [menu, setMenu] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [name, setName] = useState(project.name);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const editable = editableHere(project);
  const rename = () => {
    const wrong = renameProblem(name, project);
    setProblem(wrong);
    if (wrong !== undefined) return;
    void projects.put(project.path, renamedDraft(project, name)).then((outcome) => {
      said(projectNote(outcome, words.keyTitle));
      if (outcome.kind !== 'failed') setRenaming(false);
    });
  };
  const item = 'mx-focus flex w-full cursor-pointer items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-body-sm text-foreground hover:bg-hover';
  return (
    <article className="relative flex flex-col rounded-xl border border-panel-edge bg-card transition-colors hover:bg-hover">
      {renaming ? (
        <div className="flex flex-col gap-2 p-4">
          <label className="flex flex-col gap-1.5">
            <span className="text-footnote font-medium text-muted">Its name</span>
            <input
              className="h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-body-sm text-foreground outline-none focus:border-primary"
              value={name}
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') rename();
                if (event.key === 'Escape') setRenaming(false);
              }}
              autoFocus
            />
          </label>
          {problem !== undefined && (
            <p role="alert" className="text-footnote text-destructive">
              {problem}
            </p>
          )}
          <div className="flex gap-2">
            <KitButton kind="primary" disabled={projects.busy !== undefined} onClick={rename}>
              Rename
            </KitButton>
            <KitButton onClick={() => setRenaming(false)}>Cancel</KitButton>
          </div>
        </div>
      ) : (
        <button type="button" onClick={pick} className="mx-focus flex cursor-pointer flex-col gap-3 rounded-xl p-4 pr-12 text-left">
          <div className="flex items-start gap-3">
            <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-hover text-muted">
              <Folder size={15} aria-hidden />
            </span>
            <span className="min-w-0 flex-1 truncate pt-1.5 text-body-sm font-medium text-foreground">{card.name}</span>
          </div>
          <span className="truncate font-mono text-micro text-muted" title={project.path}>
            {project.path === '' ? card.line : project.path}
          </span>
          {(workingLine(pulse) !== undefined || waitingLine(pulse) !== undefined) && (
            <span className="flex flex-wrap items-center gap-2">
              {workingLine(pulse) !== undefined && <StatusWord tone="good">{workingLine(pulse)}</StatusWord>}
              {waitingLine(pulse) !== undefined && <StatusWord tone="attention">{waitingLine(pulse)}</StatusWord>}
            </span>
          )}
          <span className="flex flex-wrap items-center gap-1.5">
            {sharedBy(project) === undefined ? <StatusWord tone={standing.tone}>{standing.word}</StatusWord> : <OrganizationBadge />}
            <ScopeChip scope={projectScope(project)} />
            {card.chips.map((chip) => (
              <span key={chip} className="inline-flex items-center rounded-full bg-hover px-2 py-px text-label font-medium text-muted">
                {chip}
              </span>
            ))}
          </span>
          <div className="flex items-center justify-between gap-2">
            <span className="flex -space-x-1.5">
              {project.agents.map((kind) => (
                <BrandLogo key={kind} agent={kind} name={agentLabel(kind)} size={20} className="ring-2 ring-card" />
              ))}
            </span>
            <span className="text-footnote text-muted">{pulse.lastActivity}</span>
          </div>
        </button>
      )}
      {!renaming && (
        <div className="absolute top-3 right-3">
          <button
            type="button"
            aria-label={`More for ${project.name}`}
            aria-haspopup="menu"
            aria-expanded={menu}
            onClick={() => setMenu(!menu)}
            className="mx-focus grid size-8 cursor-pointer place-items-center rounded-lg text-muted hover:bg-background hover:text-foreground"
          >
            <MoreHorizontal size={16} aria-hidden />
          </button>
          {menu && (
            <div role="menu" className="absolute top-9 right-0 z-20 flex w-52 flex-col rounded-lg border border-panel-edge bg-card p-1 shadow-[0_12px_32px_rgb(0_0_0/0.16)]" onMouseLeave={() => setMenu(false)}>
              {editable ? (
                <button
                  type="button"
                  role="menuitem"
                  className={item}
                  onClick={() => {
                    setMenu(false);
                    setName(project.name);
                    setProblem(undefined);
                    setRenaming(true);
                  }}
                >
                  <Pencil size={14} aria-hidden />
                  Rename
                </button>
              ) : (
                <button type="button" role="menuitem" className={item} onClick={() => (setMenu(false), parts.host.openPage(cloudProjectLink(project)))}>
                  <ExternalLink size={14} aria-hidden />
                  {OPEN_IN_CLOUD}
                </button>
              )}
              {project.path.trim() !== '' && (
                <button type="button" role="menuitem" className={item} onClick={() => (setMenu(false), void openOrCopy(parts.host, project.path).then((opened) => !opened && said(`Copied ${project.path}.`)))}>
                  <FolderOpen size={14} aria-hidden />
                  Show its folder
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </article>
  );
}

/** The folder to take in as a project, typed whole, since the folders the sessions ran in are offered above. */
function OpenFolderForm({ busy, cancel, open }: { busy: boolean; cancel: () => void; open: (folder: string) => void }) {
  const [folder, setFolder] = useState('');
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const go = () => {
    const wrong = folderProblem(folder);
    setProblem(wrong);
    if (wrong === undefined) open(folder);
  };
  return (
    <div className="flex flex-col gap-2 rounded-xl border border-panel-edge bg-card p-4">
      <label className="flex flex-col gap-1.5">
        <span className="text-footnote font-medium text-muted">Its folder, from the top of the drive</span>
        <input
          className="h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 font-mono text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary"
          value={folder}
          placeholder="/home/you/code/project"
          onChange={(event) => setFolder(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && go()}
          autoFocus
        />
      </label>
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
      <p className="text-footnote text-muted">Opening hands its instructions to its agents at once. Whatever widens an agent waits for your signature on the island.</p>
      <div className="flex gap-2">
        <KitButton kind="primary" icon={FolderOpen} disabled={busy} onClick={go}>
          {busy ? 'Adding' : 'Add'}
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
    return <EmptyState icon={FolderGit2} title="No projects yet" body="A project appears once an agent works in a repository on this computer, with every agent that has worked there." />;
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
      <GoLink onClick={() => go({ destination: 'agents', tab: 'list' })}>Its agents</GoLink>
      <p className="text-footnote text-muted">{`Last active ${ago(workspace.lastActiveAt, Date.now()) ?? 'a while ago'}.`}</p>
    </div>
  );
}
