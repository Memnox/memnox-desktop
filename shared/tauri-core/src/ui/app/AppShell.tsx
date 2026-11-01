import {
  BookOpen,
  Brain,
  ChevronLeft,
  ChevronRight,
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
  PanelLeft,
  Plug,
  Search,
  Server,
  Settings,
  ShieldCheck,
  Sun,
  type LucideIcon,
} from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import {
  destinationInfo,
  destinationSymbol,
  DESTINATIONS,
  LANDING,
  pageSymbol,
  paneHeading,
  sameRoute,
  shownPages,
  SIDEBAR_TREE,
  WAITING_HINT,
  WAITING_ROUTE,
  WAITING_TITLE,
  type SidebarBranch,
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
} from '../../core/domain/destinations';
import { pageNamed } from '../../core/domain/settings-pages';
import { MemnoxTile, PageTitle } from '../settings/kit';
import { PageBody } from '../settings/SettingsApp';
import { useLook, useObserved, type SettingsParts } from '../settings/parts';
import { CommandPalette } from './CommandPalette';
import { AgentsPage } from './pages/AgentsPage';
import { GovernancePage } from './pages/GovernancePage';
import { HomePage } from './pages/HomePage';
import { TodayPage } from './pages/TodayPage';
import { McpHubPage } from './pages/McpHubPage';
import { WorkspacesPage } from './pages/WorkspacesPage';
import { InspectorWindow, type InspectorHost } from './inspector-host';
import { ShellChoicesProvider } from './shell-choices';
import { TopBarPickers } from './TopBarPickers';
import { useWidthClass } from './use-width';
import { SubNavFrame } from './SubNav';
import { StatusWord } from './widgets';
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
  powerplug: Plug,
  'server.rack': Server,
  globe: Globe,
  'doc.text': FileText,
  gearshape: Settings,
};

const COLLAPSED_KEY = 'memnox.sidebar.collapsed';

/**
 * The Memnox window, as the Mac's `AppShellView` draws it: the sidebar on the ground with Today, Home and what waits
 * on you over the console's tree, and beside it the page in one bordered panel with rounded corners, its top bar holding
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
  const { support } = parts;
  useObserved(support);
  const width = useWidthClass();
  const history = useRef(new RouteHistory(first)).current;
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  const [palette, setPalette] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(COLLAPSED_KEY) === 'true');
  const supports = (method: string) => support.supports(method);
  const route = settled(history.current, supports);

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
      route={route}
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
          <Breadcrumb route={route} supports={supports} />
          {width !== 'compact' ? (
            <TopBarPickers width={width} />
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
          <div key={`${route.destination}/${route.tab ?? ''}`} className="mx-auto flex max-w-[1216px] flex-col gap-5 px-5 pt-4 pb-10 min-[1200px]:px-7 max-[639px]:px-3.5">
            <InspectorWindow.Provider value={inspectors}>
              {heading.kind === 'sub-nav' ? (
                <SubNavFrame title={heading.title} groups={tabGroups(route.destination, supports)} route={route} choose={(tab) => go({ destination: route.destination, tab })}>
                  <Page parts={parts} route={route} width={width} go={go} />
                </SubNavFrame>
              ) : (
                <>
                  {heading.kind === 'page' && <PageTitle title={heading.title} subtitle={heading.subtitle} />}
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

/** Where the window is, as the console's top bar says it: the destination, then its tab once there are tabs. */
function Breadcrumb({ route, supports }: { route: Route; supports: Supports }) {
  const info = destinationInfo(route.destination);
  const tabs = visibleTabs(route.destination, supports);
  const tab = tabs.length < 2 ? undefined : tabs.find((each) => each.id === route.tab);
  return (
    <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
      <span className={tab === undefined ? 'font-medium text-foreground' : 'text-muted'}>{info.title}</span>
      {tab !== undefined && (
        <>
          <span aria-hidden className="text-faint">
            /
          </span>
          <span className="truncate font-medium text-foreground">{tab.title}</span>
        </>
      )}
    </span>
  );
}

function Page({ parts, route, width, go }: { parts: SettingsParts; route: Route; width: WidthClass; go: (route: Route) => void }): ReactNode {
  switch (route.destination) {
    case 'today':
      return <TodayPage parts={parts} width={width} go={go} />;
    case 'home':
      return <HomePage parts={parts} go={go} />;
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
 * The window's one navigation, as the Mac's `AppSidebar`: the mark and a search at the top, Today, Home and what waits
 * on you, then each heading of the tree folding over its pages, and the runtime and Settings at the foot. The chosen
 * row is filled in the Memnox blue. As a rail it keeps only the icons, each named for a screen reader and on hover.
 */
function Sidebar({
  route,
  rail,
  go,
  supports,
  search,
  runtime,
  toggle,
  collapsed,
}: {
  route: Route;
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
  const today = destinationInfo('today');
  const home = destinationInfo('home');
  const settings = destinationInfo('settings');
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
        {/* Today stands first, since the window opens on it and it asks the most of the person. */}
        <NavItem icon={ICONS[destinationSymbol('today')]} title={today.title} hint={today.subtitle} rail={rail} chosen={route.destination === 'today'} onClick={() => go(LANDING)} />
        <NavItem icon={ICONS[destinationSymbol('home')]} title={home.title} hint={home.subtitle} rail={rail} chosen={route.destination === 'home'} onClick={() => go({ destination: 'home' })} />
        <NavItem icon={ICONS.tray} title={WAITING_TITLE} hint={WAITING_HINT} rail={rail} chosen={sameRoute(route, WAITING_ROUTE)} onClick={() => go(WAITING_ROUTE)} />
        {SIDEBAR_TREE.map((branch) => (
          <Branch key={branch.title} branch={branch} route={route} rail={rail} supports={supports} go={go} open={!folded.has(branch.title)} fold={(shut) => fold(branch.title, shut)} />
        ))}
      </div>
      <div className={`flex w-full flex-col gap-0.5 py-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {runtime}
        <NavItem icon={ICONS[destinationSymbol('settings')]} title={settings.title} hint={settings.subtitle} rail={rail} chosen={route.destination === 'settings'} onClick={() => go({ destination: 'settings' })} />
        {toggle !== undefined && <NavItem icon={PanelLeft} title={collapsed ? 'Show labels' : 'Hide labels'} hint="Fold the sidebar to its icons" rail={rail} chosen={false} onClick={toggle} />}
      </div>
    </nav>
  );
}

/** A heading that folds over its pages, each page a row with its own icon. On the rail the heading is one icon, going to its first page. */
function Branch({
  branch,
  route,
  rail,
  supports,
  go,
  open,
  fold,
}: {
  branch: SidebarBranch;
  route: Route;
  rail: boolean;
  supports: Supports;
  go: (route: Route) => void;
  open: boolean;
  fold: (shut: boolean) => void;
}) {
  const pages = shownPages(branch, supports);
  const here = pages.some((page) => sameRoute(page.route, route));
  // Arriving on a page under a folded heading opens it, so the chosen row is never hidden.
  useEffect(() => {
    if (here && !open) fold(false);
  }, [here]);
  const first = pages[0];
  if (first === undefined) return null;
  if (rail) return <NavItem icon={ICONS[branch.symbol]} title={branch.title} hint={first.tab.summary} rail chosen={here} onClick={() => go(first.route)} />;
  return (
    <div className="flex flex-col gap-0.5 pt-2.5">
      <button
        type="button"
        onClick={() => fold(open)}
        aria-expanded={open}
        className="mx-focus flex h-[26px] cursor-pointer items-center gap-1.5 rounded-md px-1.5 text-meta font-medium text-faint"
      >
        <ChevronRight size={10} strokeWidth={2.6} className={`w-[18px] transition-transform duration-200 ${open ? 'rotate-90' : ''}`} aria-hidden />
        <span className="truncate">{branch.title}</span>
      </button>
      {open &&
        pages.map((page) => (
          <NavItem
            key={`${page.route.destination}/${page.route.tab ?? ''}`}
            icon={ICONS[pageSymbol(page.route)]}
            title={page.tab.title}
            hint={page.tab.summary}
            rail={false}
            chosen={sameRoute(page.route, route)}
            onClick={() => go(page.route)}
          />
        ))}
    </div>
  );
}

/** One row: its icon and words, filled in the Memnox blue with white words when chosen, lit softly under the pointer. */
function NavItem({ icon: Icon, title, hint, rail, chosen, onClick }: { icon: LucideIcon; title: string; hint: string; rail: boolean; chosen: boolean; onClick: () => void }) {
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
      {!rail && <span className="truncate">{title}</span>}
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
