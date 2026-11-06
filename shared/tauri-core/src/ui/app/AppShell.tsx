import {
  BookOpen,
  Brain,
  Check,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  Cpu,
  FileText,
  Folder,
  Globe,
  House,
  Inbox,
  ListChecks,
  Menu,
  MessagesSquare,
  Monitor,
  Network,
  PanelLeft,
  Plug,
  Search,
  Server,
  Settings,
  ShieldCheck,
  Sparkles,
  Sun,
  Users,
  type LucideIcon,
} from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import {
  destinationInfo,
  destinationSymbol,
  DESTINATIONS,
  paneHeading,
  rowOf,
  rowTabs,
  sameRoute,
  shownPages,
  shownRows,
  SIDEBAR_SECTIONS,
  SIDEBAR_TOP,
  WAITING_HINT,
  WAITING_TITLE,
  type SidebarRow,
  type SidebarSection,
  type SidebarSymbol,
  type Supports,
  inspectedItem,
  inspectorAlone,
  inspectorSearch,
  RouteHistory,
  routeForPage,
  searchOf,
  settled,
  shellLayout,
  tabGroups,
  visibleTabs,
  type Route,
  type WidthClass,
  PROJECTS_ROUTE,
  projectRoute,
} from '../../core/domain/destinations';
import { pageNamed } from '../../core/domain/settings-pages';
import { BACK_TO_PROJECTS, projectCrumbs, projectSidebar, type ProjectSidebar } from '../../core/domain/project-sidebar';
import { projectRules } from '../../core/domain/project-lines';
import {
  ALL_PROJECTS_TITLE,
  projectMemorySplit,
  shared,
  SHARED_NOTE,
  SHARED_SHOWN,
  SHARED_TITLE,
  skillReach,
  switcher,
  SWITCHER_HINT,
  SWITCHER_PROMPT,
  switchRoute,
  type SharedCounts,
} from '../../core/domain/project-context';
import type { ProjectView } from '@memnox/core/wire';
import { ProjectPages } from './pages/ProjectPages';
import { KitButton, MemnoxTile, PageTitle } from '../settings/kit';
import { PageBody } from '../settings/SettingsApp';
import { useLook, useObserved, type SettingsParts } from '../settings/parts';
import { PageTabs } from './catalog';
import { CommandPalette } from './CommandPalette';
import { AgentsPage } from './pages/AgentsPage';
import { GovernancePage } from './pages/GovernancePage';
import { HomePage } from './pages/HomePage';
import { McpHubPage } from './pages/McpHubPage';
import { WorkspacesPage } from './pages/WorkspacesPage';
import { InspectorWindow, type InspectorHost } from './inspector-host';
import { ShellChoicesProvider, useShellChoices } from './shell-choices';
import { TopBarPickers } from './TopBarPickers';
import { demoOn } from '../adapters/demo';
import { useWidthClass } from './use-width';
import { SubNavFrame } from './SubNav';
import { EmptyState, ReadFailed, StatusWord } from './widgets';
import './shell.css';

/** The Mac's SF Symbols as lucide draws the nearest of each, so the two sidebars wear the same icons. */
const ICONS: Record<SidebarSymbol, LucideIcon> = {
  'sun.max': Sun,
  house: House,
  tray: Inbox,
  cpu: Cpu,
  'bubble.left.and.text.bubble.right': MessagesSquare,
  desktopcomputer: Monitor,
  folder: Folder,
  brain: Brain,
  book: BookOpen,
  'checkmark.shield': ShieldCheck,
  'list.bullet.rectangle': ListChecks,
  'point.3.connected.trianglepath.dotted': Network,
  powerplug: Plug,
  'server.rack': Server,
  globe: Globe,
  sparkles: Sparkles,
  'doc.text': FileText,
  'person.2': Users,
  'chevron.left': ChevronLeft,
  gearshape: Settings,
};

const COLLAPSED_KEY = 'memnox.sidebar.collapsed';

/**
 * The Memnox window, as the Mac's `AppShellView` draws it: the sidebar on the ground with Home, Projects, what waits on you
 * and Activity over the console's headings, and beside it the page in one bordered panel with rounded corners, its top bar holding
 * Back, Forward and where you are. It is the same window at every size, folding the sidebar to icons when narrow and to
 * a sheet on the narrowest, so nothing is lost when it is made small.
 */
export function AppShell({ parts, first }: { parts: SettingsParts; first: Route }) {
  return (
    <ShellChoicesProvider parts={parts}>
      {inspectorAlone(window.location.search) ? <AloneInspector parts={parts} route={first} /> : <Shell parts={parts} first={first} />}
    </ShellChoicesProvider>
  );
}

/** A popped out inspector: the page is drawn hidden so it reads the item, and its inspector fills the window. */
function AloneInspector({ parts, route }: { parts: SettingsParts; route: Route }) {
  useLook(parts.preferences);
  const width = useWidthClass();
  const host: InspectorHost = { alone: true, item: inspectedItem(window.location.search), popOut: undefined, close: () => parts.host.close() };
  return (
    <InspectorWindow.Provider value={host}>
      <div className="mx-app hidden" aria-hidden>
        <Page parts={parts} route={route} width={width} go={() => undefined} />
      </div>
    </InspectorWindow.Provider>
  );
}

function Shell({ parts, first }: { parts: SettingsParts; first: Route }) {
  useLook(parts.preferences);
  const { support, projects } = parts;
  useObserved(support, projects);
  const width = useWidthClass();
  const history = useRef(new RouteHistory(first)).current;
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  const [palette, setPalette] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(COLLAPSED_KEY) === 'true');
  const supports = (method: string) => support.supports(method);
  const route = settled(history.current, supports);
  const place = route.project;
  // The project a route opens, once the list is read; the sidebar swaps to its own pages only then.
  const project = place === undefined ? undefined : projects.projects?.find((each) => each.id === place.id);
  useEffect(() => {
    if (place !== undefined && projects.projects === undefined) void projects.refresh();
  }, [place?.id]);

  const go = (next: Route) => {
    history.visit(next);
    setSheet(false);
    setPalette(false);
    window.history.replaceState(null, '', searchOf(next));
    redraw();
  };
  const step = (back: boolean) => {
    if (back) history.back();
    else history.forward();
    window.history.replaceState(null, '', searchOf(history.current));
    redraw();
  };

  useEffect(
    () =>
      parts.host.onShowPage((name) => {
        const next = routeForPage(name);
        if (next !== undefined) go(next);
      }),
    [],
  );
  useEffect(() => shortcuts({ go, step, openPalette: () => setPalette(true), close: () => (palette || sheet ? (setPalette(false), setSheet(false)) : parts.host.close()) }), [palette, sheet]);

  const layout = shellLayout(width, collapsed);
  const rail = layout.sidebar === 'rail';
  const popOut = parts.host.popOut;
  const inspectors: InspectorHost = {
    alone: false,
    item: undefined,
    popOut: popOut === undefined ? undefined : (item, title) => popOut(inspectorSearch(route, item), title),
    close: () => undefined,
  };
  const heading = paneHeading(route, supports);

  const sidebar = (
    <Sidebar
      parts={parts}
      route={route}
      project={project}
      rail={rail && !sheet}
      go={go}
      supports={supports}
      search={() => setPalette(true)}
      runtime={<RuntimeStatus parts={parts} rail={rail && !sheet} />}
      toggle={
        !layout.canFold
          ? undefined
          : () => {
              localStorage.setItem(COLLAPSED_KEY, String(!collapsed));
              setCollapsed(!collapsed);
            }
      }
      collapsed={collapsed}
    />
  );
  return (
    <div className="mx-app flex h-full bg-background text-foreground" data-width={width}>
      {width !== 'compact' && sidebar}
      {/* The panel stands 8 from the window's edges and the sidebar, so its border reads all the way round. */}
      <main className={`my-2 mr-2 flex min-w-0 flex-1 flex-col overflow-hidden rounded-xl border border-panel-edge bg-card ${width === 'compact' ? 'ml-2' : ''}`}>
        <header className="flex h-12 shrink-0 items-center gap-1 px-3 min-[640px]:pr-5">
          {width === 'compact' && <IconButton icon={Menu} label="Open the menu" onClick={() => setSheet(true)} />}
          <IconButton icon={ChevronLeft} label="Back" disabled={!history.canGoBack} onClick={() => step(true)} />
          <IconButton icon={ChevronRight} label="Forward" disabled={!history.canGoForward} onClick={() => step(false)} />
          {project !== undefined && place !== undefined ? <Crumbs parts={projectCrumbs(project, place.page)} /> : <Breadcrumb route={route} supports={supports} />}
          {demoOn && <DemoBadge />}
          {width !== 'compact' ? (
            <TopBarPickers width={width} inProject={place !== undefined} />
          ) : (
            // The sidebar holds the search; with no sidebar, Go to stays in the bar.
            <button
              type="button"
              onClick={() => setPalette(true)}
              className="mx-focus ml-1 flex h-9 cursor-pointer items-center gap-2 rounded-md border border-panel-edge bg-card px-3 text-body-sm text-muted hover:bg-hover hover:text-foreground"
              aria-label="Go to anything"
            >
              <Search size={14} />
              <kbd className="rounded-md border border-panel-edge bg-hover px-1.5 text-label font-medium">Ctrl K</kbd>
            </button>
          )}
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div key={`${route.destination}/${route.tab ?? ''}/${place?.id ?? ''}/${place?.page ?? ''}`} className="mx-auto flex max-w-[1216px] flex-col gap-5 px-5 pt-4 pb-10 min-[1200px]:px-7 max-[639px]:px-3.5">
            <InspectorWindow.Provider value={inspectors}>
              {place !== undefined ? (
                <OpenProject parts={parts} project={project} page={place.page} go={go} />
              ) : heading.kind === 'sub-nav' ? (
                <SubNavFrame title={heading.title} groups={tabGroups(route.destination, supports)} route={route} choose={(tab) => go({ destination: route.destination, tab })}>
                  <Page parts={parts} route={route} width={width} go={go} />
                </SubNavFrame>
              ) : (
                <>
                  {heading.kind === 'page' && <PageTitle title={heading.title} subtitle={heading.subtitle} />}
                  <RowTabs route={route} supports={supports} go={go} />
                  <Page parts={parts} route={route} width={width} go={go} />
                </>
              )}
            </InspectorWindow.Provider>
          </div>
        </div>
      </main>
      {width === 'compact' && sheet && (
        <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true" aria-label="Menu">
          <div className="h-full bg-background shadow-2xl">{sidebar}</div>
          <button type="button" className="flex-1 cursor-default bg-black/40" aria-label="Close the menu" onClick={() => setSheet(false)} />
        </div>
      )}
      {palette && <CommandPalette supports={supports} go={go} close={() => setPalette(false)} />}
    </div>
  );
}

/** A project's page, or nothing while the list is read, or the way back when the project is gone. */
function OpenProject({ parts, project, page, go }: { parts: SettingsParts; project: ProjectView | undefined; page: NonNullable<Route['project']>['page']; go: (route: Route) => void }) {
  const { projects } = parts;
  if (project !== undefined) return <ProjectPages parts={parts} project={project} page={page} go={go} />;
  if (projects.unreadable) return <ReadFailed what="the projects" retry={() => void projects.refresh()} />;
  if (projects.projects === undefined) return null;
  return (
    <EmptyState
      icon={Folder}
      title="This project is not here any more"
      body="It may have been removed on this computer, or the organization stopped sharing it."
      action={<KitButton onClick={() => go(PROJECTS_ROUTE)}>{BACK_TO_PROJECTS}</KitButton>}
    />
  );
}

/** Where the window is inside a project: Projects, its name, then the page. */
function Crumbs({ parts }: { parts: readonly string[] }) {
  return (
    <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
      {parts.map((part, index) => (
        <span key={`${index}:${part}`} className="flex min-w-0 items-center gap-1.5">
          {index > 0 && (
            <span aria-hidden className="text-faint">
              /
            </span>
          )}
          <span className={`truncate ${index === parts.length - 1 ? 'font-medium text-foreground' : 'text-muted'}`}>{part}</span>
        </span>
      ))}
    </span>
  );
}

/** Where the window is, as the console's top bar says it: the sidebar row, then its tab once the row has tabs. */
/** Says the window shows made up data, so a demo is never taken for the person's own. */
function DemoBadge() {
  return (
    <span
      className="mr-2 shrink-0 rounded-full border border-warm/40 bg-warm/10 px-2 py-0.5 text-body-sm font-medium text-warm"
      title="Everything in this window comes from the demo fixture, and nothing reaches Memnox or your accounts."
      aria-label="Demo data: nothing here is real"
    >
      Demo data
    </span>
  );
}

function Breadcrumb({ route, supports }: { route: Route; supports: Supports }) {
  const row = rowOf(route);
  const tabs = rowTabs(route, supports);
  const title = row?.title ?? destinationInfo(route.destination).title;
  const tab = tabs.find((each) => sameRoute(each.route, route));
  const under = tab === undefined || tab.title === title ? undefined : tab;
  return (
    <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
      <span className={under === undefined ? 'font-medium text-foreground' : 'text-muted'}>{title}</span>
      {under !== undefined && (
        <>
          <span aria-hidden className="text-faint">
            /
          </span>
          <span className="truncate font-medium text-foreground">{under.title}</span>
        </>
      )}
    </span>
  );
}

/** The pages behind the chosen sidebar row, as the console's page tabs, drawn only where the row holds more than one. */
function RowTabs({ route, supports, go }: { route: Route; supports: Supports; go: (route: Route) => void }) {
  const tabs = rowTabs(route, supports);
  if (tabs.length === 0) return null;
  const key = (each: Route) => `${each.destination}/${each.tab ?? ''}`;
  return (
    <PageTabs
      label={rowOf(route)?.title ?? 'Pages'}
      tabs={tabs.map((each) => ({ id: key(each.route), title: each.title }))}
      chosen={key(route)}
      choose={(id) => {
        const next = tabs.find((each) => key(each.route) === id);
        if (next !== undefined) go(next.route);
      }}
    />
  );
}

function Page({ parts, route, width, go }: { parts: SettingsParts; route: Route; width: WidthClass; go: (route: Route) => void }): ReactNode {
  switch (route.destination) {
    // An old link to Today settles on Home, which now holds what Today showed.
    case 'today':
    case 'home':
      return <HomePage parts={parts} width={width} go={go} />;
    case 'agents':
      return <AgentsPage parts={parts} tab={route.tab} width={width} />;
    case 'workspaces':
      return <WorkspacesPage parts={parts} tab={route.tab} width={width} go={go} />;
    case 'mcp':
      return <McpHubPage parts={parts} tab={route.tab} width={width} go={go} />;
    case 'governance':
      return <GovernancePage parts={parts} tab={route.tab} width={width} go={go} />;
    case 'settings': {
      const page = pageNamed(route.tab) ?? 'account';
      // The pane header above it names the page, as the console's settings pane does.
      return (
        <div className="flex w-full max-w-[760px] flex-col gap-5">
          <PageBody page={page} parts={parts} go={(next) => go(routeForPage(next) ?? { destination: 'settings', tab: next })} />
        </div>
      );
    }
  }
}

const FOLDED_KEY = 'memnox.sidebar.folded';

function savedFolds(): ReadonlySet<string> {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(FOLDED_KEY) ?? '[]');
    return new Set(Array.isArray(saved) ? saved.filter((each): each is string => typeof each === 'string') : []);
  } catch {
    return new Set();
  }
}

/**
 * The window's one navigation, as the console's and the Mac's: the mark and a search at the top, Home, what waits on
 * you and Projects, then Your AI and Connected tools, each heading folding over its rows, and the runtime and Settings at the foot. The chosen
 * row is filled in the Memnox blue. As a rail it keeps only the icons, each named for a screen reader and on hover.
 */
function Sidebar({
  parts,
  route,
  project,
  rail,
  go,
  supports,
  search,
  runtime,
  toggle,
  collapsed,
}: {
  parts: SettingsParts;
  route: Route;
  /** The project open now, whose own pages take the place of every row and heading. */
  project: ProjectView | undefined;
  rail: boolean;
  go: (route: Route) => void;
  supports: Supports;
  search: () => void;
  runtime: ReactNode;
  toggle: (() => void) | undefined;
  collapsed: boolean;
}) {
  const [folded, setFolded] = useState(savedFolds);
  const fold = (title: string, shut: boolean) => {
    const next = new Set(folded);
    if (shut) next.add(title);
    else next.delete(title);
    localStorage.setItem(FOLDED_KEY, JSON.stringify([...next]));
    setFolded(next);
  };
  const settings = destinationInfo('settings');
  const here = rowOf(route);
  return (
    <nav aria-label="Memnox" className={`flex h-full shrink-0 flex-col bg-background ${rail ? 'w-16 items-center' : 'w-[240px]'}`}>
      <div className={`flex h-14 w-full shrink-0 items-center gap-2.5 ${rail ? 'justify-center' : 'px-4'}`}>
        <MemnoxTile size={24} />
        {!rail && <span className="flex-1 text-[15px] font-semibold tracking-[-0.02em]">Memnox</span>}
      </div>
      {!rail && (
        <div className="px-3 pb-2">
          <button
            type="button"
            onClick={search}
            title="Search everything, Ctrl K"
            aria-label="Search everything"
            className="mx-focus flex h-[30px] w-full cursor-pointer items-center gap-1.5 rounded-md border border-panel-edge bg-card px-2.5 text-body-sm text-muted hover:bg-hover"
          >
            <Search size={12} strokeWidth={2.2} aria-hidden />
            <span className="flex-1 text-left">Search</span>
            <span className="text-label font-medium text-faint">Ctrl K</span>
          </button>
        </div>
      )}
      <div className={`flex flex-1 flex-col gap-0.5 overflow-y-auto pb-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {project !== undefined ? (
          <ProjectRows parts={parts} project={project} sidebar={projectSidebar(project, route)} route={route} rail={rail} supports={supports} go={go} />
        ) : (
          <>
            {SIDEBAR_TOP.map((row) => (
              <RowItem key={row.title} row={row} rail={rail} supports={supports} chosen={row === here} go={go} />
            ))}
            {SIDEBAR_SECTIONS.map((section) => (
              <Heading key={section.title} section={section} here={here} rail={rail} supports={supports} go={go} open={!folded.has(section.title)} fold={(shut) => fold(section.title, shut)} />
            ))}
          </>
        )}
      </div>
      <div className={`flex w-full flex-col gap-0.5 py-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {runtime}
        <NavItem icon={ICONS[destinationSymbol('settings')]} title={settings.title} hint={settings.subtitle} rail={rail} chosen={route.destination === 'settings'} onClick={() => go({ destination: 'settings' })} />
        {toggle !== undefined && <NavItem icon={PanelLeft} title={collapsed ? 'Show labels' : 'Hide labels'} hint="Fold the sidebar to its icons" rail={rail} chosen={false} onClick={toggle} />}
      </div>
    </nav>
  );
}

/**
 * A project's own sidebar, as Cloudflare's for a domain: the switcher naming the project, the way back, and its own pages.
 * The pages shared with every project are left off it for now.
 */
function ProjectRows({
  parts,
  project,
  sidebar,
  route,
  rail,
  supports,
  go,
}: {
  parts: SettingsParts;
  project: ProjectView;
  sidebar: ProjectSidebar;
  route: Route;
  rail: boolean;
  supports: Supports;
  go: (route: Route) => void;
}) {
  const counts = useSharedCounts(parts, project, supports);
  const links = SHARED_SHOWN ? shared(counts, supports) : [];
  return (
    <>
      <ProjectSwitcher parts={parts} project={project} route={route} rail={rail} go={go} />
      <NavItem icon={ChevronLeft} title={sidebar.back.title} hint={sidebar.back.title} rail={rail} chosen={false} onClick={() => go(sidebar.back.route)} />
      {rail && <div className="mt-1.5 w-full border-t border-panel-edge pt-1.5" />}
      {sidebar.rows.map((row) => (
        <NavItem key={row.page} icon={ICONS[row.symbol]} title={row.title} hint={row.summary} rail={rail} chosen={row.chosen} onClick={() => go(row.route)} />
      ))}
      {links.length > 0 && (
        <div className={`flex flex-col gap-0.5 ${rail ? 'mt-1.5 items-center border-t border-panel-edge pt-1.5' : 'pt-4'}`}>
          {!rail && (
            <span className="px-1.5 pb-1 text-meta font-medium text-faint" title={SHARED_NOTE}>
              {SHARED_TITLE}
            </span>
          )}
          {links.map((link) => (
            <NavItem key={link.row} icon={ICONS[link.symbol]} title={link.title} hint={link.hint} rail={rail} chosen={false} count={link.count} onClick={() => go(link.route)} />
          ))}
        </div>
      )}
    </>
  );
}

/** How much of each shared page applies to the project, each read once its page is answered and undefined until then. */
function useSharedCounts(parts: SettingsParts, project: ProjectView, supports: Supports): SharedCounts {
  const { studio, skills, hub, memory, agents, tools } = parts;
  useObserved(studio, skills, hub, memory, agents, tools);
  useEffect(() => {
    if (supports('rules') === true && studio.rules === undefined) void studio.refresh();
    if (supports('skills-hub') === true && skills.hub === undefined) void skills.refresh();
    if (supports('mcp-hub') === true && hub.hub === undefined) void hub.refresh();
    if (supports('memory-facts') === true && memory.everything === undefined) void memory.refreshEverything();
    if (supports('agents') === true && agents.agents === undefined) void agents.refresh();
    void tools.refresh();
  }, [project.id]);
  const rules = studio.rules === undefined ? undefined : projectRules(studio.rules.rules, project).everywhere;
  const skillCount = skills.hub?.skills.filter((skill) => skillReach(skill.scope, skill.project, project) === 'every-project').length;
  const servers = hub.hub?.servers.filter((server) => server.agents.length > 0 || server.scope === 'organization').length;
  const facts = memory.everything === undefined ? undefined : projectMemorySplit(memory.everything, project).everywhere.length;
  const connectors = tools.state.reading ? undefined : tools.state.connections.filter((each) => each.connected).length;
  return {
    ...(rules === undefined ? {} : { rules }),
    ...(skillCount === undefined ? {} : { skills: skillCount }),
    ...(servers === undefined ? {} : { servers }),
    ...(facts === undefined ? {} : { memory: facts }),
    ...(agents.agents === undefined ? {} : { agents: agents.agents.length }),
    ...(connectors === undefined ? {} : { connectors }),
  };
}

/**
 * The project's name heading its sidebar, which opens every project on this computer to switch to, most recent first,
 * each with its folder and a live dot while an agent works there. Switching keeps the page, so Tools stays Tools.
 */
function ProjectSwitcher({ parts, project, route, rail, go }: { parts: SettingsParts; project: ProjectView; route: Route; rail: boolean; go: (route: Route) => void }) {
  const { projects, sessions } = parts;
  useObserved(projects, sessions);
  const { chooseProject } = useShellChoices();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  useEffect(() => {
    if (!open) return;
    sessions.start();
    return () => sessions.stop();
  }, [open]);
  const rows = switcher(projects.projects ?? [], sessions.state.cards, project.id, query);
  const place = route.project;
  const close = () => {
    setOpen(false);
    setQuery('');
  };
  const pick = (id: string) => {
    close();
    chooseProject(id);
    go(place === undefined ? projectRoute(id) : switchRoute(id, place));
  };
  const all = () => {
    close();
    chooseProject(undefined);
    go(PROJECTS_ROUTE);
  };
  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-haspopup="listbox"
        aria-expanded={open}
        title={rail ? project.name : SWITCHER_HINT}
        aria-label={`${project.name}, ${SWITCHER_HINT}`}
        className={`mx-focus flex cursor-pointer items-center gap-2 rounded-md text-left hover:bg-hover ${rail ? 'h-10 w-10 justify-center' : 'mb-1 h-9 w-full px-1.5'}`}
      >
        <Folder size={14} strokeWidth={1.9} className="w-[18px] shrink-0 text-primary" aria-hidden />
        {!rail && <span className="min-w-0 flex-1 truncate text-body-sm font-semibold text-foreground">{project.name}</span>}
        {!rail && <ChevronsUpDown size={13} className="shrink-0 text-muted" aria-hidden />}
      </button>
      {open && (
        <>
          <button type="button" aria-label="Close the project list" className="fixed inset-0 z-30 cursor-default" onClick={close} />
          <div
            role="dialog"
            aria-label={SWITCHER_HINT}
            className={`absolute top-10 z-40 flex w-72 flex-col gap-1 rounded-lg border border-panel-edge bg-card p-1.5 shadow-[0_12px_32px_rgb(0_0_0/0.16)] ${rail ? 'left-0' : 'left-0'}`}
            onKeyDown={(event) => event.key === 'Escape' && close()}
          >
            <label className="flex items-center gap-2 rounded-md border border-field-edge bg-field px-2.5">
              <Search size={13} className="text-muted" aria-hidden />
              <input autoFocus className="h-8 min-w-0 flex-1 bg-transparent text-body-sm text-foreground outline-none placeholder:text-faint" value={query} placeholder={SWITCHER_PROMPT} aria-label={SWITCHER_PROMPT} onChange={(event) => setQuery(event.target.value)} />
            </label>
            <ul role="listbox" aria-label="Projects" className="flex max-h-80 flex-col gap-0.5 overflow-y-auto">
              {rows.map((row) => (
                <li key={row.id}>
                  <button
                    type="button"
                    role="option"
                    aria-selected={row.current}
                    onClick={() => pick(row.id)}
                    className={`mx-focus flex w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-left hover:bg-hover ${row.current ? 'bg-hover' : ''}`}
                  >
                    <span className={`size-2 shrink-0 rounded-full ${row.live ? 'bg-success' : 'bg-transparent'}`} title={row.live ? 'An agent is working here now' : undefined} aria-label={row.live ? 'An agent is working here now' : undefined} />
                    <span className="flex min-w-0 flex-1 flex-col">
                      <span className="truncate text-body-sm font-medium text-foreground">{row.name}</span>
                      <span className="truncate font-mono text-micro text-muted" title={row.folder}>
                        {row.folder}
                      </span>
                    </span>
                    {row.current && <Check size={13} className="shrink-0 text-primary" aria-hidden />}
                  </button>
                </li>
              ))}
              {rows.length === 0 && <li className="px-2 py-1.5 text-footnote text-muted">No project matches that.</li>}
            </ul>
            <button type="button" onClick={all} className="mx-focus flex cursor-pointer items-center gap-2 rounded-md border-t border-panel-edge px-2 py-2 text-left text-body-sm text-foreground hover:bg-hover">
              <ChevronLeft size={13} className="text-muted" aria-hidden />
              {ALL_PROJECTS_TITLE}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

/** One row of the sidebar, going to its first page the runtime answers; a row with none is not drawn. */
function RowItem({ row, rail, supports, chosen, go }: { row: SidebarRow; rail: boolean; supports: Supports; chosen: boolean; go: (route: Route) => void }) {
  const first = shownPages(row, supports)[0];
  if (first === undefined) return null;
  const hint = row.title === WAITING_TITLE ? WAITING_HINT : first.summary;
  return <NavItem icon={ICONS[row.symbol]} title={row.title} hint={hint} rail={rail} chosen={chosen} onClick={() => go(first.route)} />;
}

/** A heading that folds over its rows. On the rail there is no heading, only each row's icon. */
function Heading({
  section,
  here,
  rail,
  supports,
  go,
  open,
  fold,
}: {
  section: SidebarSection;
  here: SidebarRow | undefined;
  rail: boolean;
  supports: Supports;
  go: (route: Route) => void;
  open: boolean;
  fold: (shut: boolean) => void;
}) {
  const rows = shownRows(section, supports);
  const holds = here !== undefined && rows.includes(here);
  // Arriving on a page under a folded heading opens it, so the chosen row is never hidden.
  useEffect(() => {
    if (holds && !open) fold(false);
  }, [holds]);
  if (rows.length === 0) return null;
  const items = rows.map((row) => <RowItem key={row.title} row={row} rail={rail} supports={supports} chosen={row === here} go={go} />);
  if (rail) return <div className="flex flex-col items-center gap-0.5 border-t border-panel-edge pt-1.5 mt-1.5">{items}</div>;
  return (
    <div className="flex flex-col gap-0.5 pt-2.5">
      <button
        type="button"
        onClick={() => fold(open)}
        aria-expanded={open}
        className="mx-focus flex h-[26px] cursor-pointer items-center gap-1.5 rounded-md px-1.5 text-meta font-medium text-faint"
      >
        <ChevronRight size={10} strokeWidth={2.6} className={`w-[18px] transition-transform duration-200 ${open ? 'rotate-90' : ''}`} aria-hidden />
        <span className="truncate">{section.title}</span>
      </button>
      {open && items}
    </div>
  );
}

/** One row: its icon and words, filled in the Memnox blue with white words when chosen, lit softly under the pointer. */
function NavItem({ icon: Icon, title, hint, rail, chosen, onClick, count }: { icon: LucideIcon; title: string; hint: string; rail: boolean; chosen: boolean; onClick: () => void; count?: number | undefined }) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={rail ? title : hint}
      aria-label={rail ? title : undefined}
      aria-current={chosen ? 'page' : undefined}
      className={`mx-focus flex cursor-pointer items-center gap-2.5 rounded-md text-body-sm transition-colors ${rail ? 'h-10 w-10 justify-center' : 'h-[30px] w-full px-1.5'} ${
        chosen ? 'bg-primary font-medium text-white' : 'text-foreground hover:bg-hover'
      }`}
    >
      <Icon size={14} strokeWidth={1.9} className={`w-[18px] shrink-0 ${chosen ? 'text-white' : 'text-primary'}`} aria-hidden />
      {!rail && <span className="flex-1 truncate text-left">{title}</span>}
      {!rail && count !== undefined && <span className={`shrink-0 tabular-nums text-meta ${chosen ? 'text-white' : 'text-muted'}`}>{count}</span>}
    </button>
  );
}

/** The runtime's standing at the sidebar's foot, read off the home the window already keeps. */
function RuntimeStatus({ parts, rail }: { parts: SettingsParts; rail: boolean }) {
  const { home } = parts;
  useObserved(home);
  const up = home.home !== undefined;
  const words = up ? 'Runtime running' : home.unavailable ? 'Runtime not answering' : 'Reaching the runtime';
  if (rail) {
    return (
      <span title={words} className="grid h-9 w-10 place-items-center">
        <span aria-label={words} className={`size-2 rounded-full ${up ? 'bg-success' : home.unavailable ? 'bg-destructive' : 'bg-faint'}`} />
      </span>
    );
  }
  return (
    <div className="flex h-9 items-center px-2">
      <StatusWord tone={up ? 'good' : home.unavailable ? 'bad' : 'quiet'}>{words}</StatusWord>
    </div>
  );
}

function IconButton({ icon: Icon, label, onClick, disabled = false }: { icon: LucideIcon; label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="mx-focus grid size-9 cursor-pointer place-items-center rounded-lg text-muted hover:bg-hover hover:text-foreground disabled:cursor-default disabled:opacity-35 disabled:hover:bg-transparent"
    >
      <Icon size={16} />
    </button>
  );
}

interface ShortcutActions {
  go: (route: Route) => void;
  step: (back: boolean) => void;
  openPalette: () => void;
  close: () => void;
}

/** Whether a key went to somewhere the person types, where a digit is theirs rather than a shortcut. */
function typing(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target.isContentEditable || target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
}

/** Ctrl or Cmd with K opens the palette, with a digit opens a destination; Alt and an arrow go back or forward. */
function shortcuts(actions: ShortcutActions): () => void {
  const keys = (event: KeyboardEvent) => {
    const command = event.ctrlKey || event.metaKey;
    if (command && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      actions.openPalette();
      return;
    }
    const numbered = DESTINATIONS.find((each) => each.key === event.key);
    // A digit typed into a field belongs to the field, so the destinations wait until focus leaves it.
    if (command && numbered !== undefined && !typing(event.target)) {
      event.preventDefault();
      actions.go({ destination: numbered.id });
      return;
    }
    if (event.altKey && event.key === 'ArrowLeft') actions.step(true);
    if (event.altKey && event.key === 'ArrowRight') actions.step(false);
    if (event.key === 'Escape') actions.close();
  };
  window.addEventListener('keydown', keys);
  return () => window.removeEventListener('keydown', keys);
}
