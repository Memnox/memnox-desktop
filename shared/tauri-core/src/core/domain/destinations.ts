import { pageInfo, pageNamed, type SettingsPage } from './settings-pages';

/**
 * The Memnox window's five destinations and Settings, the same on the Mac, Windows and Linux. A tab
 * that needs a daemon method is shown only once the daemon answers it, so nothing on screen is a promise.
 */

export type Destination = 'home' | 'agents' | 'workspaces' | 'mcp' | 'governance' | 'settings';

/** The headings a destination's sub navigation groups its tabs under, as the console's settings tree does. */
export type TabGroupId =
  | 'agents'
  | 'computer'
  | 'projects'
  | 'knowledge'
  | 'skills'
  | 'hub'
  | 'apps'
  | 'review'
  | 'rules'
  | 'record'
  | 'account'
  | 'devices'
  | 'voice'
  | 'app';

const GROUP_TITLES: Record<TabGroupId, string> = {
  agents: 'Agents',
  computer: 'This computer',
  projects: 'Projects',
  knowledge: 'Knowledge',
  skills: 'Skills',
  hub: 'Hub',
  apps: 'Apps',
  review: 'Waiting on you',
  rules: 'Rules',
  record: 'Record',
  account: 'Account',
  devices: 'Devices',
  voice: 'Voice',
  app: 'App',
};

export interface TabInfo {
  readonly id: string;
  readonly title: string;
  /** The heading it sits under in the destination's sub navigation. */
  readonly group: TabGroupId;
  /** One line under the pane's title saying what the tab is for. */
  readonly summary: string;
  /** The daemon method this tab reads; absent when the tab needs nothing new. */
  readonly needs?: string;
}

export interface TabGroup {
  readonly id: TabGroupId;
  readonly title: string;
  readonly tabs: readonly TabInfo[];
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

/** What stays under Settings, in the order its sub navigation groups them. */
export const SETTINGS_TABS: readonly SettingsPage[] = [
  'account',
  'permissions',
  'connection',
  'phones',
  'network',
  'sync',
  'voice',
  'listening',
  'dictation',
  'appearance',
  'backup',
  'help',
];

/** Who a settings change is about: the person, their devices, the voice, or this app. */
const SETTINGS_GROUP: Record<SettingsPage, TabGroupId> = {
  account: 'account',
  permissions: 'account',
  connection: 'account',
  phones: 'devices',
  network: 'devices',
  sync: 'devices',
  voice: 'voice',
  listening: 'voice',
  dictation: 'voice',
  appearance: 'app',
  backup: 'app',
  help: 'app',
  overview: 'app',
  tools: 'app',
  apps: 'app',
};

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
      { id: 'list', title: 'Agents', group: 'agents', summary: 'The agents on this computer and what each can reach.', needs: 'agents' },
      { id: 'sessions', title: 'Sessions', group: 'agents', summary: 'What each agent is doing: what needs you, what runs, and what is done.' },
      { id: 'computer', title: 'On this computer', group: 'computer', summary: 'The agents on this computer and the apps Memnox can act in as you.' },
    ],
  },
  {
    id: 'workspaces',
    title: 'Workspaces',
    subtitle: 'Your projects, with the skills, tools, memory and rules each one carries.',
    key: '3',
    tabs: [
      { id: 'projects', title: 'Workspaces', group: 'projects', summary: 'Your projects, with the skills, tools, memory and rules each one carries.' },
      { id: 'memory', title: 'Memory', group: 'knowledge', summary: 'What your agents know, each fact with the evidence it was read from, and the sources it came out of.', needs: 'memory-facts' },
      { id: 'skills', title: 'My Skills', group: 'skills', summary: 'The skills you keep, and the agents each one is given to.', needs: 'skills-hub' },
      { id: 'assigned', title: 'Assigned', group: 'skills', summary: 'Which skills each agent carries.', needs: 'skills-hub' },
      { id: 'discover', title: 'Discover', group: 'skills', summary: 'The community index. Installing makes nothing live until you accept it.', needs: 'index-list' },
      { id: 'profiles', title: 'Profiles', group: 'projects', summary: 'Named bundles of skills, servers and a rule pack, each piece given to an agent only once you sign.', needs: 'profiles' },
    ],
  },
  {
    id: 'mcp',
    title: 'MCP Hub',
    subtitle: 'Servers set up once and given to the agents you choose.',
    key: '4',
    tabs: [
      { id: 'servers', title: 'Servers', group: 'hub', summary: 'Servers set up once and given to the agents you choose.', needs: 'mcp-hub' },
      { id: 'clients', title: 'Clients', group: 'hub', summary: 'Which agent has which server, set in one place.', needs: 'mcp-hub' },
      { id: 'secrets', title: 'Secrets', group: 'hub', summary: 'Each secret by name, where it is used, and whether this computer holds it.', needs: 'mcp-hub' },
      { id: 'apps', title: 'Your apps', group: 'apps', summary: 'Connect any tool you use as yourself, and see the ones this computer already reaches.' },
    ],
  },
  {
    id: 'governance',
    title: 'Governance',
    subtitle: 'What your agents may do, what waits on you, and what happened.',
    key: '5',
    tabs: [
      { id: 'approvals', title: 'Approvals', group: 'review', summary: 'What waits on you, oldest first, each saying what the agent wants to do and where.' },
      { id: 'policies', title: 'Policies', group: 'rules', summary: 'What your agents may do, ask about first, or never do.', needs: 'rules' },
      { id: 'activity', title: 'Activity', group: 'record', summary: 'What your agents did, newest first, beside what was decided.', needs: 'activity' },
      { id: 'learn', title: 'Learn', group: 'review', summary: 'What was read out of your sources, waiting for you to confirm or reject it.', needs: 'memory-learn' },
    ],
  },
  {
    id: 'settings',
    title: 'Settings',
    subtitle: 'This computer, your account, and the voice.',
    tabs: SETTINGS_TABS.map((page) => {
      const needs = SETTINGS_NEEDS[page];
      const info = pageInfo(page);
      return { id: page, title: info.title, group: SETTINGS_GROUP[page], summary: info.subtitle, ...(needs === undefined ? {} : { needs }) };
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

/**
 * The tabs shown now under their headings, in the order the headings first appear, an empty heading
 * dropped so a group never stands over nothing.
 */
export function tabGroups(id: Destination, supports: Supports): readonly TabGroup[] {
  const groups: { id: TabGroupId; tabs: TabInfo[] }[] = [];
  for (const tab of visibleTabs(id, supports)) {
    const known = groups.find((group) => group.id === tab.group);
    if (known === undefined) groups.push({ id: tab.group, tabs: [tab] });
    else known.tabs.push(tab);
  }
  return groups.map((group) => ({ id: group.id, title: GROUP_TITLES[group.id], tabs: group.tabs }));
}

/** The tab a route names, with its heading, for the pane's own header. */
export function tabOf(route: Route): { tab: TabInfo; group: string } | undefined {
  const tab = destinationInfo(route.destination).tabs.find((each) => each.id === route.tab);
  return tab === undefined ? undefined : { tab, group: GROUP_TITLES[tab.group] };
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

/** How the shell lays itself out at a width: the sidebar with labels, as icons or as a sheet, and the inspector beside the page, floating over it or over the whole window. */
export interface ShellLayout {
  readonly sidebar: 'labels' | 'rail' | 'sheet';
  readonly inspector: 'beside' | 'drawer' | 'full';
  /** Whether the sidebar offers to fold, which it does only where labels fit. */
  readonly canFold: boolean;
}

export function shellLayout(width: WidthClass, collapsed: boolean): ShellLayout {
  switch (width) {
    case 'wide':
      return { sidebar: collapsed ? 'rail' : 'labels', inspector: 'beside', canFold: true };
    case 'medium':
      return { sidebar: collapsed ? 'rail' : 'labels', inspector: 'drawer', canFold: true };
    case 'narrow':
      return { sidebar: 'rail', inspector: 'full', canFold: false };
    case 'compact':
      return { sidebar: 'sheet', inspector: 'full', canFold: false };
  }
}

/** The link a popped out inspector opens on: the page it came from, the item, and that only the inspector is drawn. */
export function inspectorSearch(route: Route, item: string): string {
  return `${searchOf(route)}&inspect=${encodeURIComponent(item)}&alone=1`;
}

/** The item a link names for its inspector, which a page opens with that item picked. */
export function inspectedItem(search: string): string | undefined {
  const item = queryOf(search).get('inspect');
  return item === undefined || item === '' ? undefined : item;
}

/** Whether the window is a popped out inspector, drawing nothing but the details of one item. */
export function inspectorAlone(search: string): boolean {
  return queryOf(search).get('alone') === '1' && inspectedItem(search) !== undefined;
}

export interface Command {
  readonly route: Route;
  readonly title: string;
  /** The destination it sits under, shown beside it in the palette. */
  readonly under: string;
  /** The digit that opens it with Command or Ctrl, on a destination that has one. */
  readonly key?: string;
}

/** Every place the palette can go, in sidebar order. */
export function commands(supports: Supports): readonly Command[] {
  return DESTINATIONS.flatMap((each) => {
    const top: Command = { route: { destination: each.id }, title: each.title, under: '', ...(each.key === undefined ? {} : { key: each.key }) };
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
