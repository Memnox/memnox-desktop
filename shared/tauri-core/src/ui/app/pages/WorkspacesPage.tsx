import type { ProjectView } from '@memnox/core/wire';
import { Ellipsis, Folder, FolderOpen, FolderPlus, Pencil, Plus, Search, Trash2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import { projectRoute, type Route, type WidthClass } from '../../../core/domain/destinations';
import { folderProblem } from '../../../core/domain/launch-lines';
import { insideProject } from '../../../core/domain/shell-lines';
import { foldersToOpen, FROM_ORGANIZATION, OPEN_LINE, projectCard, projectNote, ProjectsPageLines, projectStanding } from '../../../core/domain/project-lines';
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
import { ago, SEPARATOR } from '../../../core/domain/session-text';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { GoLink } from './HomePage';
import { DiscoverPage } from './DiscoverPage';
import { MemoryPage, MemorySourcesPage } from './MemoryPage';
import {
  cloudProjectLink,
  editableHere,
  NAME_PROMPT,
  REMOVE_IN_CLOUD,
  REMOVE_LINE,
  REMOVE_TITLE,
  RENAME_IN_CLOUD,
  RENAME_TITLE,
  renamedDraft,
  renameHeading,
  renameProblem,
} from '../../../core/domain/project-sidebar';
import { AgentLogos, OrganizationBadge } from './ProjectPages';
import { SkillsPage } from './SkillsPage';
import { Inspector } from '../widgets';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';
import { BrandLogo, Button, Card, CardGrid, EmptyState, ErrorLine, Field, IconButton, Input, Menu, MenuItem, MenuSeparator, Note, Panel, PRESS_DIP, Pressable, ReadFailed, Row, SearchInput, Section, Spinner, StatTile, StatusWord } from '../../kit';

/** Where a seen repository's sessions are listed. */
const SESSIONS_ROUTE: Route = { destination: 'agents', tab: 'list' };

/**
 * Projects as the runtime keeps them, with what each gives the agents opened in it. A runtime too old to
 * answer `projects` still shows every repository a session ran in, with who worked there.
 */
export function WorkspacesPage({ parts, tab, width, go }: { parts: SettingsParts; tab: string | undefined; width: WidthClass; go: (route: Route) => void }) {
  const { support } = parts;
  useObserved(support);
  if (tab === 'skills' || tab === 'assigned') return <SkillsPage parts={parts} tab={tab} width={width} />;
  // The Memory row's three tabs, the map, the list and the layers, are one page drawn three ways.
  if (tab === 'map' || tab === 'memory' || tab === 'layers') return <MemoryPage parts={parts} tab={tab} width={width} go={go} />;
  // Where memory is read from, under Inputs beside the connectors, as Memnox Cloud places its sources.
  if (tab === 'sources') return <MemorySourcesPage parts={parts} />;
  if (tab === 'discover') return <DiscoverPage parts={parts} width={width} />;
  if (support.supports('projects') === true) return <ProjectsTab parts={parts} go={go} />;
  return <SeenTab parts={parts} width={width} go={go} />;
}

/** How long the list waits before opening the live feed of held calls again after the daemon went away. */
const HELD_RECONNECT_MS = 2_000;

/**
 * The project list, as the Mac's ProjectsDestination draws it: the count, a search once there are many and Choose a
 * folder, then a card each, most recently active first, saying who works there now and what waits on the person there,
 * and at the foot the folders the agents already worked in, each one press from being a project. Opening one swaps the
 * sidebar for that project's own pages.
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
  // The folder being added, so its button says so and the others wait.
  const [adding, setAdding] = useState<string | undefined>(undefined);
  const { chooseProject } = useShellChoices();
  const all = projects.projects;
  if (all === undefined) return projects.unreadable ? <ReadFailed what={ProjectsPageLines.theProjects} retry={() => void projects.refresh()} /> : <Spinner />;
  // Every project shows here: the list is where a person picks one, so nothing narrows it.
  const list = matching(recent(all), query);
  const seen = workspacesFrom(sessions.state.cards, Date.now());
  const open = new Set(foldersToOpen(seen.map((each) => ({ path: each.path, name: each.name })), all).map((each) => each.path));
  const folders = seen.filter((each) => open.has(each.path));
  const places = calls.state.waiting.entries.map((entry) => entry.card.place);
  const busy = projects.busy !== undefined;
  const openProject = (id: string) => {
    chooseProject(id);
    go(projectRoute(id));
  };
  // Takes a folder in through the daemon's own open, then opens the project it became, as the Mac does.
  const add = (folder: string) => {
    const wrong = folderProblem(folder);
    if (wrong !== undefined) return setNote(wrong);
    setAdding(folder);
    void projects.open(folder).then((outcome) => {
      setAdding(undefined);
      setNote(projectNote(outcome, parts.words.keyTitle));
      if (outcome.kind === 'failed') return;
      setOpening(false);
      const made = projects.projects?.find((each) => insideProject(folder, each) && insideProject(each.path, { path: folder }));
      if (made !== undefined) openProject(made.id);
    });
  };
  // The system's own folder dialog, as the Mac opens Finder's; the typed form stands in only in the browser preview.
  const choose = () => {
    const pick = parts.host.pickProjectFolder;
    if (pick === undefined) return setOpening(!opening);
    void pick().then(
      (folder) => folder !== undefined && add(folder),
      (why: unknown) => setNote(String(why)),
    );
  };
  return (
    <div className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-wrap items-center gap-3">
        {all.length > 0 && <p className="text-footnote text-muted">{ProjectsPageLines.countLine(all.length)}</p>}
        <span className="min-w-2 flex-1" />
        {all.length >= SEARCH_FROM && (
          <div className="w-full" style={{ maxWidth: PROJECT_SEARCH_WIDTH }}>
            <SearchInput value={query} placeholder={SEARCH_PROMPT} onChange={setQuery} />
          </div>
        )}
        <Button
          kind={all.length === 0 ? 'primary' : 'secondary'}
          icon={FolderPlus}
          disabled={busy}
          onClick={choose}
          title={OPEN_LINE}
          {...(parts.host.pickProjectFolder === undefined ? { 'aria-expanded': opening } : {})}
        >
          {adding === undefined ? CHOOSE_TITLE : ProjectsPageLines.adding}
        </Button>
      </div>
      {opening && <OpenFolderForm busy={busy} cancel={() => setOpening(false)} open={add} />}
      {note !== undefined && <Note roomy>{note}</Note>}
      {all.length === 0 ? (
        <EmptyState icon={FolderPlus} title={EMPTY_TITLE} body={EMPTY_LINE} />
      ) : list.length === 0 ? (
        <EmptyState icon={Search} title={ProjectsPageLines.noMatch} body={ProjectsPageLines.noMatchBody} />
      ) : (
        <CardGrid min={PROJECT_CARD_MIN}>
          {list.map((each) => (
            <ProjectCard key={each.id} parts={parts} project={each} pulse={pulse(each, sessions.state.cards, places, Date.now())} pick={() => openProject(each.id)} said={setNote} />
          ))}
        </CardGrid>
      )}
      {folders.length > 0 && <Suggestions folders={folders} busy={busy} adding={adding} add={add} />}
    </div>
  );
}

/** The Mac's Projects grid lays its cards out no narrower than this. */
const PROJECT_CARD_MIN = 280;

/** The search beside Choose a folder stays this narrow, so the count keeps its line. */
const PROJECT_SEARCH_WIDTH = 240;

/** A folder glyph beside a name, as the button glyphs are. */
const FOLDER_GLYPH = 14;

/** The logos of a seen repository, overlapping, and of an agent in its overview. */
const SEEN_LOGO = 20;
const OVERVIEW_LOGO = 24;

/** The folders the agents already worked in that are not projects yet, each made one with a single press. */
function Suggestions({ folders, busy, adding, add }: { folders: readonly SeenWorkspace[]; busy: boolean; adding: string | undefined; add: (folder: string) => void }) {
  return (
    <Section title={SUGGESTIONS_TITLE}>
      <p className="text-footnote text-muted">{SUGGESTIONS_NOTE}</p>
      <Panel>
        {folders.map((each) => (
          <Row
            key={each.path}
            leading={<Folder size={FOLDER_GLYPH} className="text-muted" aria-hidden />}
            title={each.name}
            caption={<span title={each.path}>{[each.path, each.lastActive === undefined ? undefined : ProjectsPageLines.active(each.lastActive)].filter((part) => part !== undefined).join(SEPARATOR)}</span>}
            trailing={
              <>
                <AgentLogos agents={each.agents.map((agent) => agent.kind)} />
                <Button icon={Plus} disabled={busy} onClick={() => add(each.path)} aria-label={ProjectsPageLines.addAsProject(each.name)}>
                  {adding === each.path ? ProjectsPageLines.adding : ADD_TITLE}
                </Button>
              </>
            }
          />
        ))}
      </Panel>
      <p className="text-footnote text-muted">{OPEN_LINE}</p>
    </Section>
  );
}

const PULSE_DOT: Record<'good' | 'attention' | 'quiet', string> = { good: 'bg-success', attention: 'bg-warm', quiet: 'bg-faint' };
const PULSE_TEXT: Record<'good' | 'attention' | 'quiet', string> = { good: 'font-medium text-success', attention: 'font-medium text-warm', quiet: 'text-muted' };

/** One line of a card's pulse: a dot in its tone beside the words. */
function PulseLine({ tone, children }: { tone: 'good' | 'attention' | 'quiet'; children: string }) {
  return (
    <span className="flex min-w-0 items-center gap-1.5">
      <span className={`size-1.5 shrink-0 rounded-full ${PULSE_DOT[tone]}`} aria-hidden />
      <span className={`truncate text-meta ${PULSE_TEXT[tone]}`}>{children}</span>
    </span>
  );
}

/**
 * One project as the Mac's Projects grid draws it: its name and standing, its folder, what it is for, who works there
 * now and what waits there, a memory chip and the agents given it, and a menu to rename or remove it. A press anywhere
 * else opens it. An organization's project is renamed and removed in Memnox Cloud, since this computer cannot change it.
 */
function ProjectCard({ parts, project, pulse, pick, said }: { parts: SettingsParts; project: ProjectView; pulse: ProjectPulse; pick: () => void; said: (note: string) => void }) {
  const { projects, words } = parts;
  const standing = projectStanding(project);
  const card = projectCard(project);
  const [menu, setMenu] = useState(false);
  const [renaming, setRenaming] = useState<string | undefined>(undefined);
  const editable = editableHere(project);
  const working = workingLine(pulse);
  const waiting = waitingLine(pulse);
  const save = () => {
    if (renaming !== undefined && renameProblem(renaming, project) === undefined) {
      void projects.put(project.path, renamedDraft(project, renaming)).then((outcome) => said(projectNote(outcome, words.keyTitle)));
    }
    setRenaming(undefined);
  };
  if (renaming !== undefined) {
    return (
      <Card as="article" chosen className="flex flex-col gap-3">
        <p className="text-footnote font-medium text-muted">{renameHeading(project)}</p>
        <Input value={renaming} placeholder={NAME_PROMPT} onValue={setRenaming} onSubmit={save} autoFocus />
        <div className="flex gap-2">
          <Button kind="primary" disabled={projects.busy !== undefined || renameProblem(renaming, project) !== undefined} onClick={save}>
            {ProjectsPageLines.save}
          </Button>
          <Button onClick={() => setRenaming(undefined)}>{ProjectsPageLines.cancel}</Button>
        </div>
      </Card>
    );
  }
  return (
    <article className="relative flex flex-col rounded-card border border-panel-edge bg-card transition-colors hover:bg-hover">
      <Pressable
        onClick={pick}
        aria-label={[project.name, editable ? standing.word : FROM_ORGANIZATION, working, waiting, pulse.lastActivity].filter((part) => part !== undefined).join(', ')}
        className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-card p-4 text-left ${PRESS_DIP}`}
      >
        <span className="flex items-center gap-2">
          <Folder size={FOLDER_GLYPH} className="shrink-0 text-muted" aria-hidden />
          <span className="min-w-0 truncate text-body font-semibold text-foreground">{card.name}</span>
          <span className="min-w-1.5 flex-1" />
          {editable ? <StatusWord tone={standing.tone}>{standing.word}</StatusWord> : <OrganizationBadge />}
          {/* Room for the menu laid over the corner, outside the card's own button. */}
          <span className="w-6 shrink-0" aria-hidden />
        </span>
        <span className="truncate text-meta text-muted" title={project.path}>
          {project.path}
        </span>
        <span className="line-clamp-2 min-h-[2lh] text-footnote text-foreground">{card.line}</span>
        <span className="flex flex-col gap-1">
          {working !== undefined && <PulseLine tone="good">{working}</PulseLine>}
          {waiting !== undefined && <PulseLine tone="attention">{waiting}</PulseLine>}
          <PulseLine tone="quiet">{pulse.lastActivity}</PulseLine>
        </span>
        <span className="flex items-center gap-1.5">
          {card.chips.map((chip) => (
            <span key={chip} className="inline-flex items-center rounded-full bg-hover px-2.5 py-0.5 text-label font-medium text-muted">
              {chip}
            </span>
          ))}
          <span className="min-w-2 flex-1" />
          <AgentLogos agents={project.agents} />
        </span>
      </Pressable>
      <div className="absolute top-3 right-3">
        <IconButton icon={Ellipsis} size="xs" iconSize={FOLDER_GLYPH} label={ProjectsPageLines.more(project.name)} aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(!menu)} />
        {menu && (
          <Menu className="absolute top-7 right-0 z-20 w-60" onMouseLeave={() => setMenu(false)}>
            {editable ? (
              <>
                <MenuItem onPress={() => (setMenu(false), setRenaming(project.name))}>
                  <Pencil size={FOLDER_GLYPH} aria-hidden />
                  {RENAME_TITLE}
                </MenuItem>
                <MenuSeparator />
                <MenuItem disabled>
                  <Trash2 size={FOLDER_GLYPH} aria-hidden />
                  {REMOVE_TITLE}
                </MenuItem>
                <p className="px-2.5 pb-1.5 text-footnote text-muted">{REMOVE_LINE}</p>
              </>
            ) : (
              <>
                <MenuItem onPress={() => (setMenu(false), parts.host.openPage(cloudProjectLink(project)))}>
                  <Pencil size={FOLDER_GLYPH} aria-hidden />
                  {RENAME_IN_CLOUD}
                </MenuItem>
                <MenuItem onPress={() => (setMenu(false), parts.host.openPage(cloudProjectLink(project)))}>
                  <Trash2 size={FOLDER_GLYPH} aria-hidden />
                  {REMOVE_IN_CLOUD}
                </MenuItem>
              </>
            )}
          </Menu>
        )}
      </div>
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
    <Card className="flex flex-col gap-2">
      <Field label={ProjectsPageLines.folderLabel}>
        <Input wide mono value={folder} placeholder={ProjectsPageLines.folderPlaceholder} onValue={setFolder} onSubmit={go} autoFocus />
      </Field>
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
      <p className="text-footnote text-muted">{OPEN_LINE}</p>
      <div className="flex gap-2">
        <Button kind="primary" icon={FolderOpen} disabled={busy} onClick={go}>
          {busy ? ProjectsPageLines.adding : ProjectsPageLines.add}
        </Button>
        <Button onClick={cancel}>{ProjectsPageLines.cancel}</Button>
      </div>
    </Card>
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
    return <EmptyState icon={Folder} title={ProjectsPageLines.noProjects} body={ProjectsPageLines.noProjectsBody} />;
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
    <Pressable
      onClick={pick}
      aria-pressed={chosen}
      className={`mx-focus flex cursor-pointer flex-col gap-3 rounded-card border bg-card p-4 text-left hover:bg-hover ${PRESS_DIP} ${chosen ? 'border-primary' : 'border-panel-edge'}`}
    >
      <div className="flex items-center gap-2">
        <Folder size={FOLDER_GLYPH} className="text-muted" aria-hidden />
        <span className="truncate text-body font-semibold text-foreground">{workspace.name}</span>
      </div>
      <span className="truncate font-code text-micro text-muted">{workspace.path}</span>
      <div className="flex items-center justify-between gap-2">
        <span className="flex -space-x-1.5">
          {workspace.agents.map((agent) => (
            <BrandLogo key={agent.kind} agent={agent.kind} name={agent.name} size={SEEN_LOGO} className="ring-2 ring-card" />
          ))}
        </span>
        <span className="text-footnote text-muted">{workspace.lastActive === undefined ? '' : ProjectsPageLines.active(workspace.lastActive)}</span>
      </div>
    </Pressable>
  );
}

function WorkspaceOverview({ workspace, go }: { workspace: SeenWorkspace; go: (route: Route) => void }) {
  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-2.5">
        <StatTile value={workspace.agents.length} label={ProjectsPageLines.agents(workspace.agents.length)} />
        <StatTile value={workspace.sessions} label={ProjectsPageLines.sessions(workspace.sessions)} />
      </div>
      <Section title={ProjectsPageLines.agentsHere}>
        <div className="flex flex-col gap-2">
          {workspace.agents.map((agent) => (
            <div key={agent.kind} className="flex items-center gap-2.5">
              <BrandLogo agent={agent.kind} name={agent.name} size={OVERVIEW_LOGO} />
              <span className="text-body text-foreground">{agent.name}</span>
            </div>
          ))}
        </div>
      </Section>
      <GoLink onClick={() => go(SESSIONS_ROUTE)}>{ProjectsPageLines.itsSessions}</GoLink>
      <p className="text-footnote text-muted">{ProjectsPageLines.lastActive(ago(workspace.lastActiveAt, Date.now()))}</p>
    </div>
  );
}
