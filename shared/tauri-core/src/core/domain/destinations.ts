import { pageInfo, pageNamed, type SettingsPage } from './settings-pages';

/**
 * The window's pages, one per row of the sidebar, named and ordered as `shared/ux/contract.json` names them for the
 * console, the Mac, Windows and Linux alike. A page or tab that needs a daemon method shows only once the daemon
 * answers it, so nothing on screen is a promise. Mirrors the Mac's `Destinations`.
 */
export type Destination =
  | 'home'
  | 'needs-you'
  | 'sessions'
  | 'agents'
  | 'projects'
  | 'work'
  | 'rules'
  | 'hand-over'
  | 'activity'
  | 'memory'
  | 'connectors'
  | 'machines'
  | 'settings';

/** The heading a page sits under in the sidebar: none for the top rows, Govern, Knowledge, or the foot. */
export type SidebarGroup = 'top' | 'govern' | 'knowledge' | 'foot';

const GROUP_HEADINGS: Record<SidebarGroup, string | undefined> = {
  top: undefined,
  govern: 'Govern',
  knowledge: 'Knowledge',
  foot: undefined,
};

/** The heading's words, undefined where the rows stand without one, as the console's first rows and its foot do. */
export function groupHeading(group: SidebarGroup): string | undefined {
  return GROUP_HEADINGS[group];
}

/** The headings Settings groups its pages under, as the console's settings tree does. */
export type TabGroupId = 'account' | 'devices' | 'voice' | 'app';

const GROUP_TITLES: Record<TabGroupId, string> = {
  account: 'Account',
  devices: 'Devices',
  voice: 'Voice',
  app: 'App',
};

/** A Settings heading's words. */
export function groupTitle(id: TabGroupId): string {
  return GROUP_TITLES[id];
}

export interface TabInfo {
  readonly id: string;
  readonly title: string;
  /** The heading it sits under in Settings' tree; absent on a page's tab strip, which has no headings. */
  readonly group?: TabGroupId;
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

/** The icon a sidebar row wears, named as the Mac's SF Symbol is so both sidebars read alike. */
export type SidebarSymbol =
  | 'house'
  | 'tray'
  | 'rectangle.stack'
  | 'cpu'
  | 'folder'
  | 'checklist'
  | 'checkmark.shield'
  | 'gauge.with.dots.needle.67percent'
  | 'clock.arrow.circlepath'
  | 'brain'
  | 'square.grid.2x2'
  | 'desktopcomputer'
  | 'gearshape'
  | 'chevron.left';

export interface DestinationInfo {
  readonly id: Destination;
  readonly title: string;
  readonly subtitle: string;
  readonly symbol: SidebarSymbol;
  readonly group: SidebarGroup;
  /** The daemon method a page with no tabs reads, absent when it needs nothing new. */
  readonly needs?: string;
  readonly tabs: readonly TabInfo[];
}

/** Settings pages that moved to a page of their own, so a link to one still lands. */
const MOVED: Partial<Record<SettingsPage, Route>> = {
  overview: { destination: 'home' },
  tools: { destination: 'agents', tab: 'this-computer' },
  apps: { destination: 'connectors', tab: 'systems' },
  connection: { destination: 'machines' },
};

/** What stays under Settings, in the order its tree groups them; Connection stands as Machines now. */
export const SETTINGS_TABS: readonly SettingsPage[] = ['account', 'permissions', 'phones', 'voice', 'listening', 'dictation', 'appearance', 'help'];

/** Who a settings change is about: the person, their devices, the voice, or this app. */
const SETTINGS_GROUP: Partial<Record<SettingsPage, TabGroupId>> = {
  account: 'account',
  permissions: 'account',
  phones: 'devices',
  voice: 'voice',
  listening: 'voice',
  dictation: 'voice',
  appearance: 'app',
  help: 'app',
};

/**
 * Methods a contract tab reads that no runtime serves yet, so the tab stays hidden rather than promising a page. A test
 * fails the day the runtime declares one, so it leaves this list rather than lingering.
 */
export const NOT_YET_SERVED: readonly string[] = ['waiting-kept', 'decided', 'rule-changes', 'rules-history', 'budgets', 'autopilot', 'findings'];

export const DESTINATIONS: readonly DestinationInfo[] = [
  { id: 'home', title: 'Home', subtitle: 'What your agents can do on their own, and what still needs you.', symbol: 'house', group: 'top', tabs: [] },
  {
    id: 'needs-you',
    title: 'Needs you',
    subtitle: 'What waits on you, oldest first, each saying what the agent wants to do and where.',
    symbol: 'tray',
    group: 'top',
    tabs: [
      { id: 'decide-now', title: 'Decide now', summary: 'Calls held for you, and what was read from your sources, waiting for a yes or a no.' },
      { id: 'kept', title: 'Kept for later', summary: 'Questions nobody answered in time, kept so a later yes lets the retry through.', needs: 'waiting-kept' },
      { id: 'decided', title: 'Decided', summary: 'What was answered lately, and by whom.', needs: 'decided' },
      { id: 'rule-changes', title: 'Rule changes', summary: 'Rules proposed by an agent or a teammate, waiting for your signature.', needs: 'rule-changes' },
    ],
  },
  {
    id: 'sessions',
    title: 'Sessions',
    subtitle: 'Every session on this computer by status: what needs you, what was stopped, what runs and what finished.',
    symbol: 'rectangle.stack',
    group: 'top',
    tabs: [],
  },
  {
    id: 'agents',
    title: 'Agents',
    subtitle: 'The agents on this computer, what each is for, and what each can reach.',
    symbol: 'cpu',
    group: 'top',
    tabs: [
      { id: 'agents', title: 'Agents', summary: 'The agents on this computer and what each can reach.', needs: 'agents' },
      { id: 'jobs', title: 'Jobs', summary: 'What each agent is for, who answers for it, and the agents each job works through.', needs: 'profiles' },
      { id: 'this-computer', title: 'On this computer', summary: 'The agents on this computer and the apps Memnox can act in as you.' },
    ],
  },
  { id: 'projects', title: 'Projects', subtitle: 'Your projects, with the skills, tools, memory and rules each one carries.', symbol: 'folder', group: 'top', tabs: [] },
  { id: 'work', title: 'Work', subtitle: 'Which agent carries which issue, where it stands, and what waits on you.', symbol: 'checklist', group: 'top', needs: 'agent-work', tabs: [] },
  {
    id: 'rules',
    title: 'Rules',
    subtitle: 'For each thing your AI might do, choose Allow, Ask or Deny. Nothing changes until you save and the change is approved.',
    symbol: 'checkmark.shield',
    group: 'govern',
    tabs: [
      { id: 'rules', title: 'Rules', summary: 'What each agent may do, and what it asks first.', needs: 'rules' },
      { id: 'history', title: 'History', summary: 'Every change to your rules, and a way back to any of them.', needs: 'rules-history' },
    ],
  },
  {
    id: 'hand-over',
    title: 'Hand over',
    subtitle: 'What you could let your agents do on their own, what they may spend, and what autopilot gave them.',
    symbol: 'gauge.with.dots.needle.67percent',
    group: 'govern',
    tabs: [
      { id: 'ready', title: 'Ready to hand over', summary: 'What you said yes to often enough that it could run without asking.' },
      { id: 'budgets', title: 'Budgets', summary: 'How much each kind of action may happen in a window, and how much has.', needs: 'budgets' },
      { id: 'autopilot', title: 'Autopilot', summary: 'What autopilot let an agent do on its own, and a way to take it back.', needs: 'autopilot' },
    ],
  },
  {
    id: 'activity',
    title: 'Activity',
    subtitle: 'What your agents did, newest first, beside what was decided.',
    symbol: 'clock.arrow.circlepath',
    group: 'govern',
    tabs: [
      { id: 'timeline', title: 'Timeline', summary: 'What your agents did, newest first, beside what was decided.', needs: 'activity' },
      { id: 'caught', title: 'What was caught', summary: 'What Memnox stopped or would have stopped, and why.', needs: 'findings' },
    ],
  },
  {
    id: 'memory',
    title: 'Memory',
    subtitle: 'What your agents know, and the skills they carry.',
    symbol: 'brain',
    group: 'knowledge',
    tabs: [
      { id: 'map', title: 'Map', summary: 'Your agents and everything they reach, drawn as one map of what they know and use.', needs: 'memory-facts' },
      { id: 'list', title: 'List', summary: 'What your agents know, each fact with the evidence it was read from, and the sources it came out of.', needs: 'memory-facts' },
      { id: 'layers', title: 'Layers', summary: 'MEMORY.md, the router and the skills each project keeps, as the three layers any agent reads.', needs: 'memory-layers' },
      { id: 'skills', title: 'Skills', summary: 'The skills you keep, and the agents each one is given to.', needs: 'skills-hub' },
    ],
  },
  {
    id: 'connectors',
    title: 'Connectors',
    subtitle: 'The tools your agents reach, the files their memory is read from, and the MCP servers they share.',
    symbol: 'square.grid.2x2',
    group: 'knowledge',
    tabs: [
      { id: 'systems', title: 'Systems', summary: 'Connect any tool you use as yourself, and see the ones this computer already reaches.' },
      { id: 'files', title: 'Files', summary: "Where your agents' memory is read from: notes, instruction files, exports and memory servers.", needs: 'memory-facts' },
      { id: 'mcp', title: 'MCP servers', summary: 'Servers set up once and given to the agents you choose, and the secrets they use.', needs: 'mcp-hub' },
    ],
  },
  { id: 'machines', title: 'Machines', subtitle: 'The Memnox service on this computer, and the key that signs your yes.', symbol: 'desktopcomputer', group: 'foot', tabs: [] },
  {
    id: 'settings',
    title: 'Settings',
    subtitle: 'This computer, your account, and the voice.',
    symbol: 'gearshape',
    group: 'foot',
    tabs: SETTINGS_TABS.map((page) => {
      const info = pageInfo(page);
      const group = SETTINGS_GROUP[page];
      return { id: page, title: info.title, summary: info.subtitle, ...(group === undefined ? {} : { group }) };
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
export const PROJECTS_ROUTE: Route = { destination: 'projects' };

/** A page of one project, its Overview unless another is named; a page left off lands on the Overview too. */
export function projectRoute(id: string, page: ProjectPage = 'overview'): Route {
  return { ...PROJECTS_ROUTE, project: { id, page: isProjectPage(page) ? page : 'overview' } };
}

function isProjectPage(name: string | undefined): name is ProjectPage {
  return PROJECT_PAGE_IDS.some((each) => each === name);
}

/** Where the window opens: Home, which holds what needs the person below the greeting. */
export const LANDING: Route = { destination: 'home' };

/** Where a held call waits, which a notification and Home's waiting block open. */
export const WAITING_ROUTE: Route = { destination: 'needs-you', tab: 'decide-now' };

/** Where what happened is read, which Home's Today block opens. */
export const ACTIVITY_ROUTE: Route = { destination: 'activity', tab: 'timeline' };

/** Where the Memory row lands: the map, with the list, the layers and the skills beside it. */
export const MEMORY_ROUTE: Route = { destination: 'memory', tab: 'map' };

/** One heading of the sidebar and the pages under it. */
export interface SidebarSection {
  readonly group: SidebarGroup;
  readonly title: string | undefined;
  readonly rows: readonly Destination[];
}

/** The headings above the foot, in order, read off `DESTINATIONS` so no second list is kept beside it. */
export const SIDEBAR_SECTIONS: readonly SidebarSection[] = (['top', 'govern', 'knowledge'] as const).map((group) => ({
  group,
  title: groupHeading(group),
  rows: DESTINATIONS.filter((each) => each.group === group).map((each) => each.id),
}));

/** The pages at the foot, Settings last. */
export const SIDEBAR_FOOT: readonly Destination[] = DESTINATIONS.filter((each) => each.group === 'foot').map((each) => each.id);

/** One tab of a page's strip, with the words its tab and its header wear. */
export interface SidebarPage {
  readonly route: Route;
  readonly title: string;
  readonly summary: string;
}

/** A page's tabs the runtime answers now, in its order. */
export function shownPages(id: Destination, supports: Supports): readonly SidebarPage[] {
  return visibleTabs(id, supports).map((tab) => ({ route: { destination: id, tab: tab.id }, title: tab.title, summary: tab.summary }));
}

/** Whether a page shows now: one with tabs while any tab does, one without while its own method is answered. */
export function isShown(id: Destination, supports: Supports): boolean {
  const info = destinationInfo(id);
  if (info.tabs.length > 0) return visibleTabs(id, supports).length > 0;
  return info.needs === undefined || supports(info.needs) === true;
}

/** Where a press on a row lands: its first tab shown, the page itself when it has none, undefined while it shows nothing. */
export function rowTarget(id: Destination, supports: Supports): Route | undefined {
  if (!isShown(id, supports)) return undefined;
  return shownPages(id, supports)[0]?.route ?? { destination: id };
}

/** The tabs across the top of a page, shown only where there is more than one; Settings keeps a tree instead. */
export function rowTabs(route: Route, supports: Supports): readonly SidebarPage[] {
  if (route.destination === 'settings') return [];
  const pages = shownPages(route.destination, supports);
  return pages.length > 1 ? pages : [];
}

export function destinationSymbol(destination: Destination): SidebarSymbol {
  return destinationInfo(destination).symbol;
}

export function sameRoute(a: Route, b: Route): boolean {
  return a.destination === b.destination && a.tab === b.tab && a.project?.id === b.project?.id && a.project?.page === b.project?.page;
}

/** What heads the pane, as the Mac's `AppShellView.heading` decides it. */
export type PaneHeading =
  | { readonly kind: 'none' }
  | { readonly kind: 'page'; readonly title: string; readonly subtitle: string }
  | { readonly kind: 'sub-nav'; readonly title: string };

/** Settings keeps its tree beside the page; every other page shows its tab's title and line, and Home neither. */
export function paneHeading(route: Route): PaneHeading {
  const info = destinationInfo(route.destination);
  if (route.destination === 'home') return { kind: 'none' };
  const shown = tabOf(route);
  if (shown === undefined) return { kind: 'page', title: info.title, subtitle: info.subtitle };
  if (route.destination === 'settings') return { kind: 'sub-nav', title: info.title };
  return { kind: 'page', title: shown.title, subtitle: shown.summary };
}

/** Whether the daemon answers a method: true, false, or undefined while nobody has asked yet. */
export type Supports = (method: string) => boolean | undefined;

/**
 * The agents list stays shown while the person is signed in to Memnox Cloud, even with no daemon answering, since the
 * workspace's hosted and app agents are listed there; every other method is the daemon's own answer.
 */
export function withWorkspaceAgents(supports: Supports, signedIn: boolean): Supports {
  return (method) => {
    const answer = supports(method);
    return method === 'agents' && signedIn && answer !== true ? true : answer;
  };
}

export function destinationInfo(id: Destination): DestinationInfo {
  // Every Destination is listed above, so the find always lands.
  return DESTINATIONS.find((each) => each.id === id) as DestinationInfo;
}

/** The digit that opens a page with Ctrl or Cmd: the first nine rows of the sidebar, in its order. */
export function keyOf(id: Destination): string | undefined {
  const at = DESTINATIONS.findIndex((each) => each.id === id);
  return at >= 0 && at < 9 ? String(at + 1) : undefined;
}

/** The tabs shown now: those needing nothing, and those whose method the daemon answered. */
export function visibleTabs(id: Destination, supports: Supports): readonly TabInfo[] {
  return destinationInfo(id).tabs.filter((tab) => tab.needs === undefined || supports(tab.needs) === true);
}

/** Settings' tabs shown now under their headings, in the order the headings first appear. */
export function tabGroups(id: Destination, supports: Supports): readonly TabGroup[] {
  const groups: { id: TabGroupId; tabs: TabInfo[] }[] = [];
  for (const tab of visibleTabs(id, supports)) {
    if (tab.group === undefined) continue;
    const known = groups.find((group) => group.id === tab.group);
    if (known === undefined) groups.push({ id: tab.group, tabs: [tab] });
    else known.tabs.push(tab);
  }
  return groups.map((group) => ({ id: group.id, title: GROUP_TITLES[group.id], tabs: group.tabs }));
}

/** The tab a route names, for the pane's own header. */
export function tabOf(route: Route): TabInfo | undefined {
  return destinationInfo(route.destination).tabs.find((each) => each.id === route.tab);
}

/** The route as it will be drawn: a missing or hidden tab falls back to the first one shown. */
export function settled(route: Route, supports: Supports): Route {
  const tabs = visibleTabs(route.destination, supports);
  const project = route.project === undefined ? {} : { project: route.project };
  if (tabs.length === 0) return { destination: route.destination, ...project };
  const tab = tabs.find((each) => each.id === route.tab) ?? tabs[0];
  // A project's page stays open while its tab is still the one shown.
  return { destination: route.destination, tab: tab?.id, ...(tab?.id === route.tab ? project : {}) };
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

/** Pages an old link names that are no longer pages of their own, and where each went. */
const OLD_PAGES: Readonly<Record<string, Route>> = {
  today: LANDING,
  approvals: WAITING_ROUTE,
  learn: WAITING_ROUTE,
  governance: WAITING_ROUTE,
};

/** A page a settings link names, as a route, for the host's "show this page" requests. */
export function routeForPage(name: string): Route | undefined {
  const old = OLD_PAGES[name];
  if (old !== undefined) return old;
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
  /** The page it sits under, shown beside it in the palette. */
  readonly under: string;
  /** The digit that opens it with Command or Ctrl, on a page that has one. */
  readonly key?: string;
}

/** Every place the palette can go, in sidebar order, each page with its tabs under it. */
export function commands(supports: Supports): readonly Command[] {
  return DESTINATIONS.filter((each) => isShown(each.id, supports)).flatMap((each) => {
    const key = keyOf(each.id);
    const top: Command = { route: { destination: each.id }, title: each.title, under: '', ...(key === undefined ? {} : { key }) };
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
