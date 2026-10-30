import { Bot, ChevronLeft, ChevronRight, FolderGit2, House, Menu, PanelLeftClose, PanelLeftOpen, Plug, Search, Settings, ShieldCheck, type LucideIcon } from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import {
  destinationInfo,
  DESTINATIONS,
  inspectedItem,
  inspectorAlone,
  inspectorSearch,
  RouteHistory,
  routeForPage,
  searchOf,
  settled,
  shellLayout,
  tabGroups,
  tabOf,
  visibleTabs,
  type Destination,
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
import { McpHubPage } from './pages/McpHubPage';
import { WorkspacesPage } from './pages/WorkspacesPage';
import { InspectorWindow, type InspectorHost } from './inspector-host';
import { ShellChoicesProvider } from './shell-choices';
import { TopBarPickers } from './TopBarPickers';
import { useWidthClass } from './use-width';
import { SubNavFrame } from './SubNav';
import { StatusWord } from './widgets';
import './shell.css';

const ICONS: Record<Destination, LucideIcon> = {
  home: House,
  agents: Bot,
  workspaces: FolderGit2,
  mcp: Plug,
  governance: ShieldCheck,
  settings: Settings,
};

const COLLAPSED_KEY = 'memnox.sidebar.collapsed';

/**
 * The Memnox window: a sidebar of five destinations with Settings and the runtime at its foot, a light
 * top bar, and the page. It is the same window at every size, folding the sidebar to icons when narrow
 * and to a sheet on the narrowest, so nothing is lost when it is made small.
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
  const info = destinationInfo(route.destination);
  const tabs = visibleTabs(route.destination, supports);
  const shown = tabs.length < 2 ? undefined : tabOf(route);

  const sidebar = (
    <Sidebar
      route={route}
      rail={rail && !sheet}
      go={go}
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
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden bg-background">
        {/* As tall as the sidebar's head, so the two rules meet at the corner as the console's do. */}
        <header className="flex h-14 shrink-0 items-center gap-1 border-b border-panel-edge px-3 min-[640px]:px-5">
          {width === 'compact' && <IconButton icon={Menu} label="Open the menu" onClick={() => setSheet(true)} />}
          <IconButton icon={ChevronLeft} label="Back" disabled={!history.canGoBack} onClick={() => step(true)} />
          <IconButton icon={ChevronRight} label="Forward" disabled={!history.canGoForward} onClick={() => step(false)} />
          <span className="flex min-w-0 flex-1 items-center gap-1.5 truncate pl-2 text-body-sm">
            <span className={shown === undefined ? 'font-medium text-foreground' : 'text-muted'}>{info.title}</span>
            {shown !== undefined && (
              <>
                <span aria-hidden className="text-faint">
                  /
                </span>
                <span className="truncate font-medium text-foreground">{shown.tab.title}</span>
              </>
            )}
          </span>
          <TopBarPickers width={width} />
          <button
            type="button"
            onClick={() => setPalette(true)}
            className="mx-focus ml-1 flex h-9 cursor-pointer items-center gap-2 rounded-lg border border-panel-edge bg-card px-3 text-body-sm text-muted hover:bg-hover hover:text-foreground"
            aria-label="Go to anything"
          >
            <Search size={14} />
            {width !== 'compact' && <span>Go to</span>}
            <kbd className="rounded-md border border-panel-edge bg-hover px-1.5 text-label font-medium">Ctrl K</kbd>
          </button>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div key={`${route.destination}/${route.tab ?? ''}`} className="mx-auto flex max-w-[1216px] flex-col gap-5 px-5 pt-6 pb-10 min-[1200px]:px-7 max-[639px]:px-3.5">
            <InspectorWindow.Provider value={inspectors}>
              {shown !== undefined ? (
                <SubNavFrame title={info.title} groups={tabGroups(route.destination, supports)} route={route} choose={(tab) => go({ destination: route.destination, tab })}>
                  <Page parts={parts} route={route} width={width} go={go} />
                </SubNavFrame>
              ) : (
                <>
                  {route.destination !== 'home' && <PageTitle title={info.title} subtitle={info.subtitle} />}
                  <Page parts={parts} route={route} width={width} go={go} />
                </>
              )}
            </InspectorWindow.Provider>
          </div>
        </div>
      </main>
      {width === 'compact' && sheet && (
        <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true" aria-label="Menu">
          <div className="h-full shadow-2xl">{sidebar}</div>
          <button type="button" className="flex-1 cursor-default bg-black/40" aria-label="Close the menu" onClick={() => setSheet(false)} />
        </div>
      )}
      {palette && <CommandPalette supports={supports} go={go} close={() => setPalette(false)} />}
    </div>
  );
}

function Page({ parts, route, width, go }: { parts: SettingsParts; route: Route; width: WidthClass; go: (route: Route) => void }): ReactNode {
  switch (route.destination) {
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

function Sidebar({
  route,
  rail,
  go,
  runtime,
  toggle,
  collapsed,
}: {
  route: Route;
  rail: boolean;
  go: (route: Route) => void;
  runtime: ReactNode;
  toggle: (() => void) | undefined;
  collapsed: boolean;
}) {
  const main = DESTINATIONS.filter((each) => each.id !== 'settings');
  return (
    <nav aria-label="Memnox" className={`flex h-full shrink-0 flex-col border-r border-panel-edge bg-surface ${rail ? 'w-16 items-center' : 'w-[240px]'}`}>
      <div className={`flex h-14 w-full shrink-0 items-center gap-2.5 border-b border-panel-edge ${rail ? 'justify-center' : 'px-4'}`}>
        <MemnoxTile size={26} />
        {!rail && <span className="flex-1 text-base font-semibold tracking-[-0.02em]">Memnox</span>}
        {!rail && <span className="rounded-full border border-panel-edge px-2 py-px text-[10px] font-medium tracking-[0.14em] text-muted uppercase">Local</span>}
      </div>
      <div className={`flex flex-1 flex-col gap-0.5 overflow-y-auto pt-3 pb-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {main.map((each) => (
          <NavItem key={each.id} icon={ICONS[each.id]} title={each.title} hint={each.subtitle} rail={rail} chosen={route.destination === each.id} onClick={() => go({ destination: each.id })} />
        ))}
      </div>
      <div className={`flex w-full flex-col gap-0.5 border-t border-panel-edge py-2 ${rail ? 'items-center px-2' : 'px-3'}`}>
        {runtime}
        <NavItem icon={Settings} title="Settings" hint="This computer, your account, and the voice." rail={rail} chosen={route.destination === 'settings'} onClick={() => go({ destination: 'settings' })} />
        {toggle !== undefined && <NavItem icon={collapsed ? PanelLeftOpen : PanelLeftClose} title={collapsed ? 'Show labels' : 'Hide labels'} hint="Fold the sidebar to its icons" rail={rail} chosen={false} onClick={toggle} />}
      </div>
    </nav>
  );
}

function NavItem({ icon: Icon, title, hint, rail, chosen, onClick }: { icon: LucideIcon; title: string; hint: string; rail: boolean; chosen: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={rail ? title : hint}
      aria-label={rail ? title : undefined}
      aria-current={chosen ? 'page' : undefined}
      className={`mx-focus flex min-h-9 cursor-pointer items-center gap-2.5 rounded-lg text-body-sm transition-colors ${rail ? 'w-10 justify-center' : 'w-full px-3'} ${chosen ? 'bg-active font-medium text-foreground' : 'text-muted hover:bg-hover hover:text-foreground'}`}
    >
      <Icon size={16} strokeWidth={1.9} aria-hidden />
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
