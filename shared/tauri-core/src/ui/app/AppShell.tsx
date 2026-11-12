import {
  Bot,
  Brain,
  Check,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  FolderGit2,
  Gauge,
  HardDrive,
  History,
  House,
  Inbox,
  Layers,
  ListChecks,
  Menu,
  PanelLeft,
  Plug,
  ScrollText,
  Search,
  Settings,
  type LucideIcon,
} from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import {
  destinationInfo,
  DESTINATIONS,
  keyOf,
  paneHeading,
  rowTabs,
  rowTarget,
  sameRoute,
  SIDEBAR_FOOT,
  SIDEBAR_SECTIONS,
  type Destination,
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
  withWorkspaceAgents,
  shellLayout,
  tabGroups,
  type Route,
  PROJECTS_ROUTE,
  projectRoute,
} from '../../core/domain/destinations';
import { projectCrumbs, projectSidebar, type ProjectSidebar } from '../../core/domain/project-sidebar';
import { ALL_PROJECTS_TITLE, switcher, SWITCHER_HINT, SWITCHER_PROMPT, switchRoute } from '../../core/domain/project-context';
import type { ProjectView } from '@memnox/core/wire';
import { ProjectGone, ProjectPages } from './pages/ProjectPages';
import { MemnoxTile, PageTitle } from '../settings/kit';
import { useLook, useObserved, type SettingsParts } from '../settings/parts';
import { CommandPalette } from './CommandPalette';
import { RoutePage } from './pages/RoutePage';
import { InspectorWindow, type InspectorHost } from './inspector-host';
import { ShellChoicesProvider, useShellChoices } from './shell-choices';
import { TopBarPickers } from './TopBarPickers';
import { demoOn } from '../adapters/demo';
import { useWidthClass } from './use-width';
import { SubNavFrame } from './SubNav';
import './shell.css';
import { IconButton, Popover, Pressable, ReadFailed, SearchInput, SFSymbol, SideDrawer, StatusWord, Tabs, TruncatedText, Wordmark } from '../kit';
import { ShellLines } from '../../core/domain/shell-lines';
import { useRuntimeStanding } from './runtime-standing';
import { CONNECTION_PAGE } from '../../core/domain/runtime-away';

/** The Mac's SF Symbols as lucide draws the nearest of each, so the two sidebars wear the same icons. */
const ICONS: Record<SidebarSymbol, LucideIcon> = {
  house: House,
  tray: Inbox,
  'rectangle.stack': Layers,
  cpu: Bot,
  folder: FolderGit2,
  checklist: ListChecks,
  'checkmark.shield': ScrollText,
  'gauge.with.dots.needle.67percent': Gauge,
  'clock.arrow.circlepath': History,
  brain: Brain,
  'square.grid.2x2': Plug,
  desktopcomputer: HardDrive,
  gearshape: Settings,
  'chevron.left': ChevronLeft,
};

/** Where the folded sidebar is remembered between openings. */
const COLLAPSED_KEY = 'memnox.sidebar.collapsed';

/** `AppShellView.Layout`: the top bar's 36 square presses with their 13 medium glyphs, as the Mac sizes them. */
const BAR_GLYPH = 13;
const BAR_GLYPH_STROKE = 2;

/** `AppShellView.goTo`: the magnifier at callout size beside Go to's words. */
const GO_TO_GLYPH = 14;

/**
 * `AppSidebar.Layout`: a row's glyph 13 at regular weight, the search's caption sized and medium, and a heading's
 * chevron 9 and semibold, at the stroke `SFSymbol` gives each weight.
 */
const NAV_GLYPH = 13;
const NAV_GLYPH_STROKE = 1.75;
const SEARCH_GLYPH = 11;
const SEARCH_GLYPH_STROKE = 2;
const FOLD_GLYPH = 9;
const FOLD_GLYPH_STROKE = 2.25;

/** The switcher's chevron is the heading's; the tick by the current project is caption sized and semibold. */
const SWITCHER_CHEVRON = FOLD_GLYPH;
const SWITCHER_TICK = 11;
/** All projects at the switcher's foot wears its symbol at the words' own 13. */
const ALL_PROJECTS_GLYPH = 13;

/** The Memnox mark at the sidebar's head. */
const BRAND_TILE = 24;
/** `AppSidebar.Layout.wordmark`: the name's height at the sidebar's head. */
const BRAND_WORDMARK = 15;

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
        <RoutePage parts={parts} route={route} width={width} go={() => undefined} />
      </div>
    </InspectorWindow.Provider>
  );
}

function Shell({ parts, first }: { parts: SettingsParts; first: Route }) {
  useLook(parts.preferences);
  const { support, projects, workspaceAgents } = parts;
  useObserved(support, projects, workspaceAgents);
  // Read once, so a person signed in with no daemon still finds their workspace's agents under AI agents.
  useEffect(() => {
    void workspaceAgents.refresh();
  }, []);
  const width = useWidthClass();
  const history = useRef(new RouteHistory(first)).current;
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  const [palette, setPalette] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(COLLAPSED_KEY) === 'true');
  const supports = withWorkspaceAgents((method: string) => support.supports(method), workspaceAgents.signedIn);
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
  const heading = paneHeading(route);

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
      {/* The panel stands off the window's edges and the sidebar, so its border reads all the way round. */}
      <main className={`my-shell-panel-inset mr-shell-panel-inset flex min-w-0 flex-1 flex-col overflow-hidden rounded-card border border-panel-edge bg-card ${width === 'compact' ? 'ml-shell-panel-inset' : ''}`}>
        <header className="flex h-shell-top-bar shrink-0 items-center gap-1 px-3 narrow:pr-5">
          {width === 'compact' && <BarButton icon={Menu} label={ShellLines.openMenu} onClick={() => setSheet(true)} />}
          <BarButton icon={ChevronLeft} label={ShellLines.back} disabled={!history.canGoBack} onClick={() => step(true)} />
          <BarButton icon={ChevronRight} label={ShellLines.forward} disabled={!history.canGoForward} onClick={() => step(false)} />
          {project !== undefined && place !== undefined ? <Crumbs parts={projectCrumbs(project, place.page)} /> : <Breadcrumb route={route} supports={supports} />}
          {demoOn && <DemoBadge />}
          {width !== 'compact' ? (
            <TopBarPickers width={width} inProject={place !== undefined} />
          ) : (
            // The sidebar holds the search; with no sidebar, Go to stays in the bar.
            <Pressable
              onClick={() => setPalette(true)}
              className="mx-focus ml-1 flex h-field cursor-pointer items-center gap-2 rounded-control border border-panel-edge bg-card px-3 text-body-sm text-muted hover:bg-hover"
              aria-label={ShellLines.goTo}
              title={ShellLines.goTo}
            >
              <Search size={GO_TO_GLYPH} aria-hidden />
              <kbd className="rounded-control border border-panel-edge bg-hover px-1.5 text-label font-medium text-muted">{ShellLines.paletteKeys}</kbd>
            </Pressable>
          )}
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div key={`${route.destination}/${route.tab ?? ''}/${place?.id ?? ''}/${place?.page ?? ''}`} className="mx-auto flex max-w-shell-page flex-col gap-shell-section px-shell-side pt-shell-top pb-shell-foot wide:px-shell-side-wide max-narrow:px-shell-side-compact">
            <InspectorWindow.Provider value={inspectors}>
              {place !== undefined ? (
                <OpenProject parts={parts} project={project} page={place.page} go={go} />
              ) : heading.kind === 'sub-nav' ? (
                <SubNavFrame title={heading.title} groups={tabGroups(route.destination, supports)} route={route} choose={(tab) => go({ destination: route.destination, tab })}>
                  <RoutePage parts={parts} route={route} width={width} go={go} />
                </SubNavFrame>
              ) : (
                <>
                  {heading.kind === 'page' && <PageTitle title={heading.title} subtitle={heading.subtitle} />}
                  <RowTabs route={route} supports={supports} go={go} />
                  <RoutePage parts={parts} route={route} width={width} go={go} />
                </>
              )}
            </InspectorWindow.Provider>
          </div>
        </div>
      </main>
      {width === 'compact' && sheet && (
        <SideDrawer label={ShellLines.menu} closeLabel={ShellLines.closeMenu} onClose={() => setSheet(false)}>
          {sidebar}
        </SideDrawer>
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
  return <ProjectGone back={() => go(PROJECTS_ROUTE)} />;
}

/** Where the window is inside a project: Projects, its name, then the page. */
function Crumbs({ parts }: { parts: readonly string[] }) {
  return (
    <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
      {parts.map((part, index) => (
        <span key={`${index}:${part}`} className="flex min-w-0 items-center gap-1.5">
          {index > 0 && (
            <span aria-hidden className="text-faint">
              {ShellLines.crumbGap}
            </span>
          )}
          <span className={`truncate ${index === parts.length - 1 ? 'font-medium text-foreground' : 'text-muted'}`}>{part}</span>
        </span>
      ))}
    </span>
  );
}

/** Says the window shows made up data, so a demo is never taken for the person's own. */
function DemoBadge() {
  return (
    <span
      className="mr-2 shrink-0 rounded-full border border-warm bg-warm/[0.14] px-2 py-shell-badge-y text-body-sm font-medium text-warm"
      title={ShellLines.demoHint}
      aria-label={ShellLines.demoLabel}
    >
      {ShellLines.demoBadge}
    </span>
  );
}

/** Where the window is, as the console's top bar says it: the sidebar row, then its tab once the row has tabs. */
function Breadcrumb({ route, supports }: { route: Route; supports: Supports }) {
  const title = destinationInfo(route.destination).title;
  const tab = rowTabs(route, supports).find((each) => sameRoute(each.route, route));
  const under = tab === undefined || tab.title === title ? undefined : tab;
  return (
    <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
      <span className={under === undefined ? 'font-medium text-foreground' : 'text-muted'}>{title}</span>
      {under !== undefined && (
        <>
          <span aria-hidden className="text-faint">
            {ShellLines.crumbGap}
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
    <Tabs
      label={destinationInfo(route.destination).title}
      tabs={tabs.map((each) => ({ id: key(each.route), title: each.title }))}
      chosen={key(route)}
      choose={(id) => {
        const next = tabs.find((each) => key(each.route) === id);
        if (next !== undefined) go(next.route);
      }}
    />
  );
}

/** Where the folded sidebar headings are remembered, by title. */
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
  const { calls } = parts;
  useObserved(calls);
  // Needs you carries how many wait, on the rail too, so the one count that asks for the person is never folded away.
  const waiting = calls.state.waiting.newestFirst.length;
  const fold = (title: string, shut: boolean) => {
    const next = new Set(folded);
    if (shut) next.add(title);
    else next.delete(title);
    localStorage.setItem(FOLDED_KEY, JSON.stringify([...next]));
    setFolded(next);
  };
  return (
    <nav aria-label={ShellLines.navigation} className={`flex h-full shrink-0 flex-col bg-background ${rail ? 'w-sidebar-rail items-center' : 'w-sidebar'}`}>
      <div className={`flex h-shell-bar w-full shrink-0 items-center gap-2.5 ${rail ? 'justify-center' : 'px-4'}`}>
        {/* The name in the brand's own letters, as the Mac's sidebar heads itself; the rail has room for the mark alone. */}
        {rail ? <MemnoxTile size={BRAND_TILE} /> : <Wordmark height={BRAND_WORDMARK} className="text-foreground" />}
      </div>
      {!rail && (
        <div className="px-3 pb-2">
          <Pressable
            onClick={search}
            title={ShellLines.searchHint}
            aria-label={ShellLines.searchEverything}
            className="mx-focus flex h-sidebar-search w-full cursor-pointer items-center gap-1.5 rounded-control border border-panel-edge bg-card px-2.5 text-body-sm text-muted hover:bg-hover"
          >
            <Search size={SEARCH_GLYPH} strokeWidth={SEARCH_GLYPH_STROKE} aria-hidden />
            <span className="flex-1 text-left">{ShellLines.search}</span>
            <span className="text-label font-medium text-faint">{ShellLines.paletteKeys}</span>
          </Pressable>
        </div>
      )}
      <div className={`flex flex-1 flex-col gap-0.5 overflow-y-auto pb-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {project !== undefined ? (
          <ProjectRows parts={parts} project={project} sidebar={projectSidebar(project, route)} route={route} rail={rail} go={go} />
        ) : (
          <>
            {SIDEBAR_SECTIONS.map((section) => (
              <Heading key={section.group} section={section} here={route.destination} rail={rail} supports={supports} go={go} waiting={waiting} open={section.title === undefined || !folded.has(section.title)} fold={(shut) => section.title !== undefined && fold(section.title, shut)} />
            ))}
          </>
        )}
      </div>
      <div className={`flex w-full flex-col gap-0.5 py-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {runtime}
        {SIDEBAR_FOOT.map((id) => (
          <RowItem key={id} id={id} rail={rail} supports={supports} chosen={route.destination === id} go={go} />
        ))}
        {toggle !== undefined && <NavItem icon={PanelLeft} title={collapsed ? ShellLines.showLabels : ShellLines.hideLabels} hint={ShellLines.foldHint} rail={rail} chosen={false} onClick={toggle} />}
      </div>
    </nav>
  );
}

/**
 * A project's own sidebar, as Cloudflare's for a domain: the switcher naming the project, the way back, and its own pages.
 */
function ProjectRows({
  parts,
  project,
  sidebar,
  route,
  rail,
  go,
}: {
  parts: SettingsParts;
  project: ProjectView;
  sidebar: ProjectSidebar;
  route: Route;
  rail: boolean;
  go: (route: Route) => void;
}) {
  return (
    <>
      <NavItem icon={ChevronLeft} title={sidebar.back.title} hint={sidebar.back.title} rail={rail} chosen={false} onClick={() => go(sidebar.back.route)} />
      <ProjectSwitcher parts={parts} project={project} route={route} rail={rail} go={go} />
      {sidebar.rows.map((row) => (
        <NavItem key={row.page} icon={ICONS[row.symbol]} title={row.title} hint={row.summary} rail={rail} chosen={row.chosen} onClick={() => go(row.route)} />
      ))}
    </>
  );
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
  const press = useRef<HTMLButtonElement>(null);
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
    <>
      <Pressable
        ref={press}
        onClick={() => (open ? close() : setOpen(true))}
        aria-haspopup="dialog"
        aria-expanded={open}
        title={rail ? project.name : SWITCHER_HINT}
        aria-label={`${project.name}, ${SWITCHER_HINT}`}
        className={`mx-focus flex h-sidebar-row cursor-pointer items-center gap-1.5 rounded-control text-left hover:bg-hover ${rail ? 'w-sidebar-rail-row justify-center' : 'mt-2.5 w-full px-1.5'}`}
      >
        {rail ? (
          <FolderGit2 size={NAV_GLYPH} strokeWidth={NAV_GLYPH_STROKE} className="shrink-0 text-foreground" aria-hidden />
        ) : (
          <>
            <span className="min-w-0 flex-1 truncate text-body-sm font-semibold text-foreground">{project.name}</span>
            <ChevronsUpDown size={SWITCHER_CHEVRON} strokeWidth={FOLD_GLYPH_STROKE} className="shrink-0 text-muted" aria-hidden />
          </>
        )}
      </Pressable>
      {open && (
        // `ProjectSwitcherList`, beside its press as the Mac's popover opens on its trailing edge.
        <Popover anchor={press} side="trailing" label={SWITCHER_HINT} onClose={close} className="w-switcher gap-2 p-3">
          <SearchInput autoFocus value={query} placeholder={SWITCHER_PROMPT} onChange={setQuery} />
          <ul role="listbox" aria-label={ShellLines.projects} className="flex max-h-switcher-list flex-col gap-0.5 overflow-y-auto">
            {rows.map((row) => (
              <li key={row.id}>
                <Pressable
                  role="option"
                  aria-selected={row.current}
                  onClick={() => pick(row.id)}
                  className={`mx-focus flex h-switcher-row w-full cursor-pointer items-center gap-2.5 rounded-control px-1.5 text-left hover:bg-hover ${row.current ? 'bg-hover' : ''}`}
                >
                  <span className={`size-shell-dot shrink-0 rounded-full ${row.live ? 'bg-success' : 'bg-transparent'}`} title={row.live ? ShellLines.agentWorking : undefined} aria-label={row.live ? ShellLines.agentWorking : undefined} />
                  <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className={`truncate text-body-sm text-foreground ${row.current ? 'font-semibold' : ''}`}>{row.name}</span>
                    <TruncatedText text={row.folder} middle className="text-meta text-muted" />
                  </span>
                  {row.current && <Check size={SWITCHER_TICK} strokeWidth={FOLD_GLYPH_STROKE} className="shrink-0 text-primary" aria-hidden />}
                </Pressable>
              </li>
            ))}
            {rows.length === 0 && <li className="p-1.5 text-footnote text-muted">{ShellLines.noProjectMatches}</li>}
          </ul>
          <div className="h-px bg-panel-edge" role="separator" />
          <Pressable onClick={all} className="mx-focus flex cursor-pointer items-center gap-1.5 text-left text-body-sm text-primary">
            <SFSymbol name="square.grid.2x2" size={ALL_PROJECTS_GLYPH} />
            {ALL_PROJECTS_TITLE}
          </Pressable>
        </Popover>
      )}
    </>
  );
}

/** One row of the sidebar, going to its first page the runtime answers; a row with none is not drawn. */
function RowItem({ id, rail, supports, chosen, go, count }: { id: Destination; rail: boolean; supports: Supports; chosen: boolean; go: (route: Route) => void; count?: number | undefined }) {
  const target = rowTarget(id, supports);
  if (target === undefined) return null;
  const info = destinationInfo(id);
  return <NavItem icon={ICONS[info.symbol]} title={info.title} hint={info.subtitle} rail={rail} chosen={chosen} count={count} onClick={() => go(target)} />;
}

/** A heading that folds over its rows; the top rows stand without one. On the rail there is no heading, only each row's icon. */
function Heading({
  section,
  here,
  rail,
  supports,
  go,
  waiting,
  open,
  fold,
}: {
  section: SidebarSection;
  here: Destination;
  rail: boolean;
  supports: Supports;
  go: (route: Route) => void;
  waiting: number;
  open: boolean;
  fold: (shut: boolean) => void;
}) {
  const rows = section.rows.filter((id) => rowTarget(id, supports) !== undefined);
  const holds = rows.includes(here);
  // Arriving on a page under a folded heading opens it, so the chosen row is never hidden.
  useEffect(() => {
    if (holds && !open) fold(false);
  }, [holds]);
  if (rows.length === 0) return null;
  const items = rows.map((id) => <RowItem key={id} id={id} rail={rail} supports={supports} chosen={id === here} go={go} count={id === 'needs-you' && waiting > 0 ? waiting : undefined} />);
  // On the rail the heading gives way to a little room between the sections, as the Mac's does.
  if (rail || section.title === undefined) return <div className={`flex flex-col gap-0.5 ${section.title === undefined ? '' : 'pt-2.5'} ${rail ? 'items-center' : ''}`}>{items}</div>;
  return (
    <div className="flex flex-col gap-0.5 pt-2.5">
      <Pressable onClick={() => fold(open)} aria-expanded={open} className="mx-focus flex h-sidebar-heading cursor-pointer items-center gap-1.5 rounded-control px-1.5 text-meta font-medium text-faint">
        <ChevronRight size={FOLD_GLYPH} strokeWidth={FOLD_GLYPH_STROKE} className={`w-sidebar-icon transition-transform duration-(--mx-duration-quick) ${open ? 'rotate-90' : ''}`} aria-hidden />
        <span className="truncate">{section.title}</span>
      </Pressable>
      {open && items}
    </div>
  );
}

/** One row: its icon and words, filled in the Memnox blue with white words when chosen, lit softly under the pointer. */
function NavItem({ icon: Icon, title, hint, rail, chosen, onClick, count }: { icon: LucideIcon; title: string; hint: string; rail: boolean; chosen: boolean; onClick: () => void; count?: number | undefined }) {
  return (
    <Pressable
      onClick={onClick}
      title={rail ? title : hint}
      aria-label={rail ? (count === undefined ? title : `${title}, ${count}`) : undefined}
      aria-current={chosen ? 'page' : undefined}
      className={`mx-focus flex cursor-pointer items-center gap-2.5 rounded-control text-body-sm transition-colors ${rail ? 'size-sidebar-rail-row justify-center' : 'h-sidebar-row w-full px-1.5'} ${
        chosen ? 'bg-primary font-medium text-white' : 'text-foreground hover:bg-hover'
      }`}
    >
      <span className="relative">
        <Icon size={NAV_GLYPH} strokeWidth={NAV_GLYPH_STROKE} className={`w-sidebar-icon shrink-0 ${chosen ? 'text-white' : 'text-primary'}`} aria-hidden />
        {/* The rail drops the words, so a count rides on the icon instead of going unseen. */}
        {rail && count !== undefined && <span aria-hidden className="absolute -top-0.5 -right-1.5 size-1.5 rounded-full bg-primary" />}
      </span>
      {!rail && <span className="flex-1 truncate text-left">{title}</span>}
      {!rail && count !== undefined && <span className={`shrink-0 tabular-nums text-meta ${chosen ? 'text-white' : 'text-faint'}`}>{count}</span>}
    </Pressable>
  );
}

/** The runtime's standing at the sidebar's foot, read off the home the window already keeps. */
export function RuntimeStatus({ parts, rail }: { parts: SettingsParts; rail: boolean }) {
  const { host } = parts;
  // The last read decides, since a home kept from an earlier read outlives a runtime that stopped since.
  const standing = useRuntimeStanding(parts);
  const up = standing === 'up';
  const away = standing === 'away';
  // Away opens Connection, where Check again starts the service, so a stopped runtime is one press from running.
  const fix = away ? () => host.openSettings(CONNECTION_PAGE) : undefined;
  const words = up ? ShellLines.runtimeUp : away ? ShellLines.runtimeDown : standing === 'starting' ? ShellLines.runtimeStarting : ShellLines.runtimeReaching;
  if (rail) {
    return (
      <Pressable title={fix === undefined ? words : ShellLines.runtimeDownHint} disabled={fix === undefined} onClick={fix} className="grid h-sidebar-row w-sidebar-rail-row place-items-center">
        <span aria-label={words} className={`size-2 rounded-full ${up ? 'bg-success' : away ? 'bg-destructive' : 'bg-faint'}`} />
      </Pressable>
    );
  }
  return (
    <div className="flex min-h-sidebar-row items-center px-1.5">
      {fix === undefined ? (
        <StatusWord tone={up ? 'good' : 'quiet'}>{words}</StatusWord>
      ) : (
        <Pressable title={ShellLines.runtimeDownHint} onClick={fix} className="mx-focus cursor-pointer">
          <StatusWord tone="bad">{words}</StatusWord>
        </Pressable>
      )}
    </div>
  );
}

/** `AppShellView.iconButton`: a 36 square in muted ink, its 13 medium glyph, lit under the pointer, fading to 0.35 when it cannot go. */
function BarButton({ icon, label, onClick, disabled = false }: { icon: LucideIcon; label: string; onClick: () => void; disabled?: boolean }) {
  return <IconButton icon={icon} label={label} size="lg" iconSize={BAR_GLYPH} strokeWidth={BAR_GLYPH_STROKE} fade="bar" disabled={disabled} onClick={onClick} />;
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
    const numbered = DESTINATIONS.find((each) => keyOf(each.id) === event.key);
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
