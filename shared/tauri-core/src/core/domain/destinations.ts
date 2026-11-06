import { pageInfo, pageNamed, type SettingsPage } from './settings-pages';

/**
 * The Memnox window's five destinations and Settings, the same on the Mac, Windows and Linux. A tab
 * that needs a daemon method is shown only once the daemon answers it, so nothing on screen is a promise.
 */

export type Destination = 'today' | 'home' | 'agents' | 'workspaces' | 'mcp' | 'governance' | 'settings';

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
  review: 'Needs your attention',
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
  // Local network is left off for now, since phones reach this computer through the relay without a setting.
  'sync',
  'voice',
  'listening',
  'dictation',
  'appearance',
  // Backup is left off for now, so nobody leans on a restore that has not been tried end to end.
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
  /** What Today showed now sits on Home, so this stays only for old links, which land on Home. */
  { id: 'today', title: 'Today', subtitle: 'What needs you today, the most urgent first, and what your agents did.', tabs: [] },
  { id: 'home', title: 'Home', subtitle: 'What is running, what needs you, and where to carry on.', key: '1', tabs: [] },
  {
    id: 'agents',
    title: 'AI agents',
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
    title: 'Projects',
    subtitle: 'Your projects, with the skills, tools, memory and rules each one carries.',
    key: '3',
    tabs: [
      { id: 'projects', title: 'Projects', group: 'projects', summary: 'Your projects, with the skills, tools, memory and rules each one carries.' },
      // One page for memory, opening on the map of what the agents know and reach, with the list one switch away.
      { id: 'memory', title: 'Memory', group: 'knowledge', summary: 'What your agents know and everything they reach, drawn as one map, with every fact and its evidence one switch away.', needs: 'memory-facts' },
      { id: 'sources', title: 'Files', group: 'knowledge', summary: "Where your agents' memory is read from: notes, instruction files, exports and memory servers.", needs: 'memory-facts' },
      { id: 'skills', title: 'My Skills', group: 'skills', summary: 'The skills you keep, and the agents each one is given to.', needs: 'skills-hub' },
      { id: 'assigned', title: 'Assigned', group: 'skills', summary: 'Which skills each agent carries.', needs: 'skills-hub' },
      // Discover is left off for now, since the marketplace holds no listing yet. Profiles is left off too, because a
      // bundle handed across a team is kept in Memnox Cloud rather than on one person's computer.
    ],
  },
  {
    id: 'mcp',
    title: 'MCP Hub',
    subtitle: 'Servers set up once and given to the agents you choose.',
    key: '4',
    tabs: [
      // Servers, Clients and Secrets stand as the MCP servers row, Connectors as a row of its own.
      { id: 'servers', title: 'Servers', group: 'hub', summary: 'Servers set up once and given to the agents you choose.', needs: 'mcp-hub' },
      { id: 'clients', title: 'Clients', group: 'hub', summary: 'Which agent has which server, set in one place.', needs: 'mcp-hub' },
      { id: 'secrets', title: 'Secrets', group: 'hub', summary: 'Each secret by name, where it is used, and whether this computer holds it.', needs: 'mcp-hub' },
      { id: 'apps', title: 'Connectors', group: 'apps', summary: 'Connect any tool you use as yourself, and see the ones this computer already reaches.' },
    ],
  },
  {
    id: 'governance',
    title: 'Governance',
    subtitle: 'What your agents may do, what waits on you, and what happened.',
    key: '5',
    tabs: [
      { id: 'approvals', title: 'Approvals', group: 'review', summary: 'What waits on you, oldest first, each saying what the agent wants to do and where.' },
      { id: 'policies', title: 'Protection settings', group: 'rules', summary: 'For each thing your AI might do, choose Allow, Ask or Deny. Nothing changes until you save and the change is approved.', needs: 'rules' },
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
  /** Inside one project, which swaps the sidebar for that project's own pages. */
  readonly project?: ProjectPlace;
}

/** The pages of one project, in the order its sidebar lists them. */
export type ProjectPage = 'overview' | 'tools' | 'agents' | 'memory' | 'autonomy';

/** Tools is left off for now, since its folder shows on the Overview and Files and Connectors are pages of their own. */
export const PROJECT_PAGE_IDS: readonly ProjectPage[] = ['overview', 'agents', 'memory', 'autonomy'];

/** One project by its id, and which of its pages is shown. */
export interface ProjectPlace {
  readonly id: string;
  readonly page: ProjectPage;
}

/** The project list, which every project's Back row returns to. */
export const PROJECTS_ROUTE: Route = { destination: 'workspaces', tab: 'projects' };

/** A page of one project, its Overview unless another is named; a page left off lands on the Overview too. */
export function projectRoute(id: string, page: ProjectPage = 'overview'): Route {
  return { ...PROJECTS_ROUTE, project: { id, page: isProjectPage(page) ? page : 'overview' } };
}

function isProjectPage(name: string | undefined): name is ProjectPage {
  return PROJECT_PAGE_IDS.some((each) => each === name);
}

/** Where the window opens: Home, which holds what needs the person today below the greeting. */
export const LANDING: Route = { destination: 'home' };

/** The icon a sidebar row wears, named as the Mac's SF Symbol is so both sidebars read alike. */
export type SidebarSymbol =
  | 'sun.max'
  | 'house'
  | 'tray'
  | 'cpu'
  | 'bubble.left.and.text.bubble.right'
  | 'desktopcomputer'
  | 'folder'
  | 'brain'
  | 'book'
  | 'checkmark.shield'
  | 'list.bullet.rectangle'
  | 'point.3.connected.trianglepath.dotted'
  | 'powerplug'
  | 'server.rack'
  | 'globe'
  | 'sparkles'
  | 'doc.text'
  | 'person.2'
  | 'chevron.left'
  | 'gearshape';

/** One row of the sidebar: where it goes, and the pages behind it that its page shows as tabs. */
export interface SidebarRow {
  readonly title: string;
  readonly symbol: SidebarSymbol;
  /** The first is where a press goes; every one lights the row and stands as a tab on its page. */
  readonly pages: readonly Route[];
}

/** One heading of the sidebar and its rows. */
export interface SidebarSection {
  readonly title: string;
  readonly rows: readonly SidebarRow[];
}

/** Needs your attention stands beside Home, as in Memnox Cloud, since it is the one row that asks something of the person. */
export const WAITING_ROUTE: Route = { destination: 'governance', tab: 'approvals' };
export const WAITING_TITLE = 'Needs your attention';
export const WAITING_HINT = 'What your agents are waiting on you for';

/** Activity stands beside Needs your attention, as in Memnox Cloud, since what happened is read as often as what waits. */
export const ACTIVITY_ROUTE: Route = { destination: 'governance', tab: 'activity' };

/** The Memory row's one page, which opens on the map and holds the list behind a switch. */
export const MEMORY_ROUTE: Route = { destination: 'workspaces', tab: 'memory' };

/** Tabs that were folded into another, so an old link to one still lands on the page that holds it now. */
const FOLDED_TABS: Readonly<Record<string, string>> = { 'workspaces/map': 'memory' };

/** The rows above every heading, in the console's order: Home, the projects everything else is for, what waits, and what happened. */
export const SIDEBAR_TOP: readonly SidebarRow[] = [
  // One page, since what Today showed now sits on Home below the greeting, so no strip shows.
  { title: 'Home', symbol: 'house', pages: [{ destination: 'home' }] },
  { title: 'Projects', symbol: 'folder', pages: [{ destination: 'workspaces', tab: 'projects' }] },
  { title: WAITING_TITLE, symbol: 'tray', pages: [WAITING_ROUTE, { destination: 'governance', tab: 'learn' }] },
  { title: 'Activity', symbol: 'sun.max', pages: [ACTIVITY_ROUTE] },
];

/**
 * The headings as the console and the Mac name them, in the console's order: the AI and what it may do, then what
 * Memnox reads, which governs nothing. Each row is one subject and the pages that answer it sit behind it as tabs.
 * Meetings and People are left out because no page on this computer reads them yet, so Organization goes with them
 * and Settings stands at the foot of the sidebar rather than under a heading.
 */
export const SIDEBAR_SECTIONS: readonly SidebarSection[] = [
  {
    title: 'Your AI',
    rows: [
      {
        title: 'AI agents',
        symbol: 'cpu',
        pages: [
          { destination: 'agents', tab: 'list' },
          { destination: 'agents', tab: 'sessions' },
          { destination: 'agents', tab: 'computer' },
        ],
      },
      { title: 'Protection settings', symbol: 'checkmark.shield', pages: [{ destination: 'governance', tab: 'policies' }] },
      { title: 'Memory', symbol: 'brain', pages: [MEMORY_ROUTE] },
      // A row of its own, as the console keeps one, since a page behind another row's tab is one nobody finds.
      { title: 'Skills', symbol: 'sparkles', pages: [{ destination: 'workspaces', tab: 'skills' }, { destination: 'workspaces', tab: 'assigned' }] },
      {
        title: 'MCP servers',
        symbol: 'powerplug',
        pages: [
          { destination: 'mcp', tab: 'servers' },
          { destination: 'mcp', tab: 'clients' },
          { destination: 'mcp', tab: 'secrets' },
        ],
      },
    ],
  },
  {
    title: 'Connected tools',
    rows: [
      { title: 'Connectors', symbol: 'globe', pages: [{ destination: 'mcp', tab: 'apps' }] },
      { title: 'Files', symbol: 'doc.text', pages: [{ destination: 'workspaces', tab: 'sources' }] },
    ],
  },
];

/** One page behind a row, with the words its tab and its header wear. */
export interface SidebarPage {
  readonly route: Route;
  readonly title: string;
  readonly summary: string;
}

/** A page the runtime answers now, or undefined; a destination with no tabs is a page of its own. */
function pageOf(route: Route, supports: Supports): SidebarPage | undefined {
  const info = destinationInfo(route.destination);
  if (route.tab === undefined) return info.tabs.length === 0 ? { route, title: info.title, summary: info.subtitle } : undefined;
  const tab = visibleTabs(route.destination, supports).find((each) => each.id === route.tab);
  return tab === undefined ? undefined : { route, title: tab.title, summary: tab.summary };
}

/** A row's pages the runtime answers now, in the row's order; a row with none is not drawn. */
export function shownPages(row: SidebarRow, supports: Supports): readonly SidebarPage[] {
  return row.pages.flatMap((route) => {
    const page = pageOf(route, supports);
    return page === undefined ? [] : [page];
  });
}

/** A heading's rows that have a page to show, so a heading never stands over nothing. */
export function shownRows(section: SidebarSection, supports: Supports): readonly SidebarRow[] {
  return section.rows.filter((row) => shownPages(row, supports).length > 0);
}

/** Every row the sidebar draws, top rows first. */
export const SIDEBAR_ROWS: readonly SidebarRow[] = [...SIDEBAR_TOP, ...SIDEBAR_SECTIONS.flatMap((section) => section.rows)];

/** The row a page sits behind, which is the row lit while it is shown. */
export function rowOf(route: Route): SidebarRow | undefined {
  return SIDEBAR_ROWS.find((row) => row.pages.some((page) => sameRoute(page, route)));
}

/** The tabs across the top of a page: the row's other pages, shown only where there is more than one. */
export function rowTabs(route: Route, supports: Supports): readonly SidebarPage[] {
  const row = rowOf(route);
  const pages = row === undefined ? [] : shownPages(row, supports);
  return pages.length > 1 ? pages : [];
}

const DESTINATION_SYMBOLS: Record<Destination, SidebarSymbol> = {
  today: 'sun.max',
  home: 'house',
  agents: 'cpu',
  workspaces: 'folder',
  mcp: 'powerplug',
  governance: 'checkmark.shield',
  settings: 'gearshape',
};

const TAB_SYMBOLS: Record<string, SidebarSymbol> = {
  list: 'cpu',
  sessions: 'bubble.left.and.text.bubble.right',
  computer: 'desktopcomputer',
  projects: 'folder',
  memory: 'brain',
  skills: 'sparkles',
  servers: 'server.rack',
  apps: 'globe',
  sources: 'doc.text',
  policies: 'checkmark.shield',
  activity: 'list.bullet.rectangle',
};

export function destinationSymbol(destination: Destination): SidebarSymbol {
  return DESTINATION_SYMBOLS[destination];
}

/** Each page's icon in the tree, falling back to its destination's for a page not listed. */
export function pageSymbol(route: Route): SidebarSymbol {
  return (route.tab === undefined ? undefined : TAB_SYMBOLS[route.tab]) ?? DESTINATION_SYMBOLS[route.destination];
}

export function sameRoute(a: Route, b: Route): boolean {
  return a.destination === b.destination && a.tab === b.tab && a.project?.id === b.project?.id && a.project?.page === b.project?.page;
}

/** What heads the pane, as the Mac's `AppShellView.heading` decides it. */
export type PaneHeading =
  | { readonly kind: 'none' }
  | { readonly kind: 'page'; readonly title: string; readonly subtitle: string }
  | { readonly kind: 'sub-nav'; readonly title: string };

/**
 * Settings keeps its tree beside the page; every other page is reached from the sidebar, so it shows its row's
 * title where the row holds tabs, else its own, with its own line under it. Home and Today show neither, since
 * Today writes its own line from what waits.
 */
export function paneHeading(route: Route, supports: Supports): PaneHeading {
  const info = destinationInfo(route.destination);
  const shown = tabOf(route);
  const bare = route.destination === 'home' || route.destination === 'today';
  const row = rowTabs(route, supports).length > 1 ? rowOf(route) : undefined;
  if (route.destination !== 'settings' && !bare && shown !== undefined) return { kind: 'page', title: row?.title ?? shown.tab.title, subtitle: shown.tab.summary };
  if (visibleTabs(route.destination, supports).length > 1 && shown !== undefined) return { kind: 'sub-nav', title: info.title };
  return bare ? { kind: 'none' } : { kind: 'page', title: info.title, subtitle: info.subtitle };
}

/** Whether the daemon answers a method: true, false, or undefined while nobody has asked yet. */
export type Supports = (method: string) => boolean | undefined;

export function destinationInfo(id: Destination): DestinationInfo {
  // Every Destination is listed above, so the find always lands.
  return DESTINATIONS.find((each) => each.id === id) as DestinationInfo;
}

/**
 * Tabs left off for now, by destination and tab, so the window stays straightforward while a person finds their way:
 * Learn, the hub's Clients and Secrets, Assigned skills, Sessions and Personal sync. An old link to one settles on the
 * first tab its destination still shows. Mirrors `leftOff` in the Mac's `Destinations`.
 */
export const LEFT_OFF: readonly string[] = ['governance/learn', 'mcp/clients', 'mcp/secrets', 'workspaces/assigned', 'agents/sessions', 'settings/sync'];

/** The tabs shown now: those needing nothing, and those whose method the daemon answered, less those left off. */
export function visibleTabs(id: Destination, supports: Supports): readonly TabInfo[] {
  return destinationInfo(id).tabs.filter((tab) => !LEFT_OFF.includes(`${id}/${tab.id}`) && (tab.needs === undefined || supports(tab.needs) === true));
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
  if (route.destination === 'today') return { destination: 'home' };
  const tabs = visibleTabs(route.destination, supports);
  if (tabs.length === 0) return { destination: route.destination };
  const named = FOLDED_TABS[`${route.destination}/${route.tab ?? ''}`] ?? route.tab;
  const tab = tabs.find((each) => each.id === named) ?? tabs[0];
  // A project stays open only on the projects tab, which is the list its Back row returns to.
  const project = tab?.id === PROJECTS_ROUTE.tab ? route.project : undefined;
  return { destination: route.destination, tab: tab?.id, ...(project === undefined ? {} : { project }) };
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

/** The route a link names: `?dest=mcp&tab=servers`, or an old `?page=phones`, or Today. */
export function routeFrom(search: string): Route {
  const params = queryOf(search);
  const destination = params.get('dest');
  if (isDestination(destination)) {
    const tab = params.get('tab');
    const project = params.get('project');
    const page = params.get('part');
    const place = project === undefined || project === '' ? undefined : { id: project, page: isProjectPage(page) ? page : 'overview' };
    return { destination, ...(tab === undefined ? {} : { tab }), ...(place === undefined ? {} : { project: place }) };
  }
  const page = pageNamed(params.get('page'));
  if (page === undefined) return LANDING;
  return MOVED[page] ?? { destination: 'settings', tab: page };
}

export function searchOf(route: Route): string {
  const tab = route.tab === undefined ? '' : `&tab=${encodeURIComponent(route.tab)}`;
  const project = route.project === undefined ? '' : `&project=${encodeURIComponent(route.project.id)}&part=${route.project.page}`;
  return `?dest=${encodeURIComponent(route.destination)}${tab}${project}`;
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
  // Today folded into Home, so the palette offers Home alone for both.
  return DESTINATIONS.filter((each) => each.id !== 'today').flatMap((each) => {
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
    return this.visited[this.at] ?? LANDING;
  }

  get canGoBack(): boolean {
    return this.at > 0;
  }

  get canGoForward(): boolean {
    return this.at < this.visited.length - 1;
  }

  visit(route: Route): void {
    if (sameRoute(this.current, route)) return;
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
