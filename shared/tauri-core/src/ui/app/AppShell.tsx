import { Bot, ChevronLeft, ChevronRight, FolderGit2, House, Menu, PanelLeftClose, PanelLeftOpen, Plug, Search, Settings, ShieldCheck, type LucideIcon } from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import {
  destinationInfo,
  DESTINATIONS,
  RouteHistory,
  routeForPage,
  searchOf,
  settled,
  visibleTabs,
  type Destination,
  type Route,
  type WidthClass,
} from '../../core/domain/destinations';
import { pageInfo, pageNamed } from '../../core/domain/settings-pages';
import { MemnoxTile, PageTitle } from '../settings/kit';
import { PageBody } from '../settings/SettingsApp';
import { useLook, useObserved, type SettingsParts } from '../settings/parts';
import { CommandPalette } from './CommandPalette';
import { AgentsPage } from './pages/AgentsPage';
import { GovernancePage } from './pages/GovernancePage';
import { HomePage } from './pages/HomePage';
import { McpHubPage } from './pages/McpHubPage';
import { WorkspacesPage } from './pages/WorkspacesPage';
import { useWidthClass } from './use-width';
import { StatusWord, TabBar } from './widgets';
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

  const rail = width === 'narrow' || (collapsed && width !== 'compact');
  const info = destinationInfo(route.destination);
  const tabs = visibleTabs(route.destination, supports);
  const title = route.destination === 'settings' && route.tab !== undefined ? pageInfo(pageNamed(route.tab) ?? 'account').title : info.title;

  const sidebar = (
    <Sidebar
      route={route}
      rail={rail && !sheet}
      go={go}
      runtime={<RuntimeStatus parts={parts} rail={rail && !sheet} />}
      toggle={
        width === 'compact' || width === 'narrow'
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
    <div className="mx-app flex h-full bg-surface text-foreground" data-width={width}>
      {width !== 'compact' && sidebar}
      <main className={`flex min-w-0 flex-1 flex-col overflow-hidden bg-background ${width === 'compact' ? '' : 'my-2 mr-2 rounded-2xl border border-panel-edge'}`}>
        <header className="flex h-12 shrink-0 items-center gap-2 border-b border-panel-edge px-3">
          {width === 'compact' && <IconButton icon={Menu} label="Open the menu" onClick={() => setSheet(true)} />}
          <IconButton icon={ChevronLeft} label="Back" disabled={!history.canGoBack} onClick={() => step(true)} />
          <IconButton icon={ChevronRight} label="Forward" disabled={!history.canGoForward} onClick={() => step(false)} />
          <span className="min-w-0 flex-1 truncate pl-1 text-headline font-semibold text-foreground">{title}</span>
          <button
            type="button"
            onClick={() => setPalette(true)}
            className="mx-focus flex h-8 cursor-pointer items-center gap-2 rounded-lg border border-panel-edge bg-card px-2.5 text-footnote text-muted hover:bg-hover"
            aria-label="Go to anything"
          >
            <Search size={13} />
            {width !== 'compact' && <span>Go to</span>}
            <kbd className="rounded border border-panel-edge px-1 font-mono text-micro">Ctrl K</kbd>
          </button>
        </header>
        {route.destination !== 'settings' && <TabBar tabs={tabs} chosen={route.tab} choose={(tab) => go({ destination: route.destination, tab })} />}
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div key={`${route.destination}/${route.tab ?? ''}`} className="mx-auto flex max-w-[1180px] flex-col gap-5 px-5 pt-5 pb-8 max-[639px]:px-3.5">
            {route.destination !== 'home' && route.destination !== 'settings' && tabs.length < 2 && <p className="text-footnote text-muted">{info.subtitle}</p>}
            <Page parts={parts} route={route} width={width} go={go} />
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
      return <WorkspacesPage parts={parts} width={width} go={go} />;
    case 'mcp':
      return <McpHubPage parts={parts} tab={route.tab} width={width} />;
    case 'governance':
      return <GovernancePage parts={parts} tab={route.tab} width={width} go={go} />;
    case 'settings': {
      const page = pageNamed(route.tab) ?? 'account';
      const info = pageInfo(page);
      return (
        <div className="mx-auto flex w-full max-w-[760px] flex-col gap-5">
          <PageTitle title={info.title} subtitle={info.subtitle} />
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
    <nav aria-label="Memnox" className={`flex h-full shrink-0 flex-col bg-surface py-3 ${rail ? 'w-[60px] items-center px-2' : 'w-[232px] px-2.5'}`}>
      <div className={`flex items-center gap-2 pb-4 ${rail ? 'justify-center' : 'px-1.5'}`}>
        <MemnoxTile size={24} />
        {!rail && <span className="flex-1 text-headline font-semibold">Memnox</span>}
        {!rail && <span className="rounded-md border border-panel-edge px-1.5 text-micro text-muted">Local</span>}
      </div>
      <div className="flex flex-1 flex-col gap-0.5">
        {main.map((each) => (
          <NavItem key={each.id} icon={ICONS[each.id]} title={each.title} hint={each.subtitle} rail={rail} chosen={route.destination === each.id} onClick={() => go({ destination: each.id })} />
        ))}
      </div>
      <div className="flex flex-col gap-0.5 border-t border-panel-edge pt-2">
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
      className={`mx-focus flex h-9 cursor-pointer items-center gap-2.5 rounded-lg text-body transition-colors ${rail ? 'w-10 justify-center' : 'w-full px-2.5'} ${chosen ? 'bg-hover font-medium text-foreground' : 'text-muted hover:bg-hover hover:text-foreground'}`}
    >
      <Icon size={16} strokeWidth={1.9} className={chosen ? 'text-primary' : undefined} aria-hidden />
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
    <div className="flex h-9 items-center px-2.5">
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
      className="mx-focus grid size-8 cursor-pointer place-items-center rounded-lg text-muted hover:bg-hover hover:text-foreground disabled:cursor-default disabled:opacity-35 disabled:hover:bg-transparent"
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
    if (command && numbered !== undefined) {
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
