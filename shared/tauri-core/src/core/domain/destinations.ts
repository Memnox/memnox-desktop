import { pageInfo, pageNamed, type SettingsPage } from './settings-pages';

/**
 * The Memnox window's five destinations and Settings, the same on the Mac, Windows and Linux. A tab
 * that needs a daemon method is shown only once the daemon answers it, so nothing on screen is a promise.
 */

export type Destination = 'home' | 'agents' | 'workspaces' | 'mcp' | 'governance' | 'settings';

export interface TabInfo {
  readonly id: string;
  readonly title: string;
  /** The daemon method this tab reads; absent when the tab needs nothing new. */
  readonly needs?: string;
}

export interface DestinationInfo {
  readonly id: Destination;
  readonly title: string;
  readonly subtitle: string;
  /** The digit that opens it, with Ctrl on Windows and Linux. */
  readonly key?: string;
  readonly tabs: readonly TabInfo[];
}

/** Pages that moved out of Settings into a destination, so a link to one still lands. */
const MOVED: Partial<Record<SettingsPage, Route>> = {
  overview: { destination: 'home' },
  tools: { destination: 'agents', tab: 'computer' },
  apps: { destination: 'mcp', tab: 'apps' },
};

/** What stays under Settings, in the order the sidebar groups had them. */
export const SETTINGS_TABS: readonly SettingsPage[] = [
  'account',
  'permissions',
  'connection',
  'phones',
  'network',
  'appearance',
  'backup',
  'sync',
  'voice',
  'listening',
  'dictation',
  'help',
];

/** Settings pages that read a daemon method, hidden until the runtime answers it. */
const SETTINGS_NEEDS: Partial<Record<SettingsPage, string>> = {
  network: 'lan-status',
  sync: 'personal-sync-status',
};

export const DESTINATIONS: readonly DestinationInfo[] = [
  { id: 'home', title: 'Home', subtitle: 'What is running, what needs you, and where to carry on.', key: '1', tabs: [] },
  {
    id: 'agents',
    title: 'Agents',
    subtitle: 'The agents on this computer, their sessions, and what each can reach.',
    key: '2',
    tabs: [
      { id: 'list', title: 'Agents', needs: 'agents' },
      { id: 'sessions', title: 'Sessions' },
      { id: 'computer', title: 'On this computer' },
    ],
  },
  {
    id: 'workspaces',
    title: 'Workspaces',
    subtitle: 'Your projects, with the skills, tools, memory and rules each one carries.',
    key: '3',
    tabs: [
      { id: 'projects', title: 'Workspaces' },
      { id: 'memory', title: 'Memory', needs: 'memory-facts' },
      { id: 'skills', title: 'My Skills', needs: 'skills-hub' },
      { id: 'assigned', title: 'Assigned', needs: 'skills-hub' },
      { id: 'discover', title: 'Discover', needs: 'index-list' },
      { id: 'profiles', title: 'Profiles', needs: 'profiles' },
    ],
  },
  {
    id: 'mcp',
    title: 'MCP Hub',
    subtitle: 'Servers set up once and given to the agents you choose.',
    key: '4',
    tabs: [
      { id: 'servers', title: 'Servers', needs: 'mcp-hub' },
      { id: 'clients', title: 'Clients', needs: 'mcp-hub' },
      { id: 'secrets', title: 'Secrets', needs: 'mcp-hub' },
      { id: 'apps', title: 'Your apps' },
    ],
  },
  {
    id: 'governance',
    title: 'Governance',
    subtitle: 'What your agents may do, what waits on you, and what happened.',
    key: '5',
    tabs: [
      { id: 'approvals', title: 'Approvals' },
      { id: 'policies', title: 'Policies', needs: 'rules' },
      { id: 'activity', title: 'Activity', needs: 'activity' },
      { id: 'learn', title: 'Learn', needs: 'memory-learn' },
    ],
  },
  {
    id: 'settings',
    title: 'Settings',
    subtitle: 'This computer, your account, and the voice.',
    tabs: SETTINGS_TABS.map((page) => {
      const needs = SETTINGS_NEEDS[page];
      return { id: page, title: pageInfo(page).title, ...(needs === undefined ? {} : { needs }) };
    }),
  },
];

export interface Route {
  readonly destination: Destination;
  readonly tab?: string;
}

/** Whether the daemon answers a method: true, false, or undefined while nobody has asked yet. */
export type Supports = (method: string) => boolean | undefined;

export function destinationInfo(id: Destination): DestinationInfo {
  // Every Destination is listed above, so the find always lands.
  return DESTINATIONS.find((each) => each.id === id) as DestinationInfo;
}

/** The tabs shown now: those needing nothing, and those whose method the daemon answered. */
export function visibleTabs(id: Destination, supports: Supports): readonly TabInfo[] {
  return destinationInfo(id).tabs.filter((tab) => tab.needs === undefined || supports(tab.needs) === true);
}

/** The route as it will be drawn: a missing or hidden tab falls back to the first one shown. */
export function settled(route: Route, supports: Supports): Route {
  const tabs = visibleTabs(route.destination, supports);
  if (tabs.length === 0) return { destination: route.destination };
  const tab = tabs.find((each) => each.id === route.tab) ?? tabs[0];
  return { destination: route.destination, tab: tab?.id };
}

/** A link's query as names and values; the core has no URL parser, since it never runs in a browser alone. */
function queryOf(search: string): Map<string, string> {
  const pairs = search.replace(/^\?/, '').split('&').filter((pair) => pair !== '');
  return new Map(
    pairs.map((pair) => {
      const [name = '', value = ''] = pair.split('=');
      return [decodeURIComponent(name), decodeURIComponent(value.replace(/\+/g, ' '))];
    }),
  );
}

function isDestination(name: string | undefined | null): name is Destination {
  return DESTINATIONS.some((each) => each.id === name);
}

/** The route a link names: `?dest=mcp&tab=servers`, or an old `?page=phones`, or Home. */
export function routeFrom(search: string): Route {
  const params = queryOf(search);
  const destination = params.get('dest');
  if (isDestination(destination)) {
    const tab = params.get('tab');
    return tab === undefined ? { destination } : { destination, tab };
  }
  const page = pageNamed(params.get('page'));
  if (page === undefined) return { destination: 'home' };
  return MOVED[page] ?? { destination: 'settings', tab: page };
}

export function searchOf(route: Route): string {
  const tab = route.tab === undefined ? '' : `&tab=${encodeURIComponent(route.tab)}`;
  return `?dest=${encodeURIComponent(route.destination)}${tab}`;
}

/** A page a settings link names, as a route, for the host's "show this page" requests. */
export function routeForPage(name: string): Route | undefined {
  const page = pageNamed(name);
  if (page === undefined) return isDestination(name) ? { destination: name } : undefined;
  return MOVED[page] ?? { destination: 'settings', tab: page };
}

/** Window widths at which the layout changes, the same numbers the Mac uses. */
export const WIDTH = { WIDE: 1200, MEDIUM: 900, NARROW: 640 } as const;

/** Wide keeps the inspector beside the page, medium floats it, narrow folds the sidebar to icons, compact to a sheet. */
export type WidthClass = 'wide' | 'medium' | 'narrow' | 'compact';

export function widthClass(width: number): WidthClass {
  if (width >= WIDTH.WIDE) return 'wide';
  if (width >= WIDTH.MEDIUM) return 'medium';
  if (width >= WIDTH.NARROW) return 'narrow';
  return 'compact';
}

export interface Command {
  readonly route: Route;
  readonly title: string;
  /** The destination it sits under, shown beside it in the palette. */
  readonly under: string;
}

/** Every place the palette can go, in sidebar order. */
export function commands(supports: Supports): readonly Command[] {
  return DESTINATIONS.flatMap((each) => {
    const top: Command = { route: { destination: each.id }, title: each.title, under: '' };
    const tabs = visibleTabs(each.id, supports).map((tab) => ({
      route: { destination: each.id, tab: tab.id },
      title: tab.title,
      under: each.title,
    }));
    return [top, ...tabs];
  });
}

/** The commands whose title or destination contains every word typed, best first. */
export function matchCommands(query: string, supports: Supports): readonly Command[] {
  const words = query.trim().toLowerCase().split(/\s+/).filter((word) => word !== '');
  const all = commands(supports);
  if (words.length === 0) return all;
  const matching = all.filter((each) => {
    const text = `${each.title} ${each.under}`.toLowerCase();
    return words.every((word) => text.includes(word));
  });
  // A title that starts with what was typed is the likelier aim.
  const first = words[0] ?? '';
  return [...matching].sort((a, b) => Number(b.title.toLowerCase().startsWith(first)) - Number(a.title.toLowerCase().startsWith(first)));
}

/** Where Back and Forward go, as `PageHistory` does for pages: a visit drops whatever was ahead. */
export class RouteHistory {
  private visited: Route[];
  private at = 0;

  constructor(first: Route) {
    this.visited = [first];
  }

  get current(): Route {
    return this.visited[this.at] ?? { destination: 'home' };
  }

  get canGoBack(): boolean {
    return this.at > 0;
  }

  get canGoForward(): boolean {
    return this.at < this.visited.length - 1;
  }

  visit(route: Route): void {
    const now = this.current;
    if (now.destination === route.destination && now.tab === route.tab) return;
    this.visited = [...this.visited.slice(0, this.at + 1), route];
    this.at = this.visited.length - 1;
  }

  back(): void {
    if (this.canGoBack) this.at -= 1;
  }

  forward(): void {
    if (this.canGoForward) this.at += 1;
  }
}
