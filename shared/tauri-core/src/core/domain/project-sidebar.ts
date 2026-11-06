import type { MemoryItemView, ProjectDraft, ProjectView, ToolConnection } from '@memnox/core/wire';
import { ALL_CATEGORIES, categoryCounts, matchesSearch, searchWords, type CategoryCount } from './catalog';
import { PROJECT_PAGE_IDS, PROJECTS_ROUTE, projectRoute, sameRoute, type ProjectPage, type Route, type SidebarSymbol } from './destinations';
import { agentLabel } from './mcp-hub-lines';
import type { SharedRow } from './project-context';
import { counted, draftOf, sharedBy } from './project-lines';
import { toolkitName } from './tool-brand';

/**
 * The sidebar a project swaps in when it is opened, in the Cloudflare dashboard's way: opening a domain there trades
 * the whole sidebar for "Back to Domains" and that domain's own pages. A project is not only code, so none of its pages
 * leads with a repository. This words and orders what the daemon sent; it decides nothing.
 */

export const BACK_TO_PROJECTS = 'Back to Projects';

/** Where Memnox Cloud keeps projects, which is where anything this computer cannot save is changed. */
export const MEMNOX_CLOUD = 'https://app.memnox.com';

export const OPEN_IN_CLOUD = 'Open in Memnox Cloud';

interface ProjectPageInfo {
  readonly page: ProjectPage;
  readonly title: string;
  readonly symbol: SidebarSymbol;
  /** One line under the page's title saying what it is for. */
  readonly summary: string;
}

const PAGE_INFO: Readonly<Record<ProjectPage, Omit<ProjectPageInfo, 'page'>>> = {
  overview: { title: 'Overview', symbol: 'house', summary: 'What this project is, what it still needs, and what it learned lately.' },
  // Left off the sidebar for now, and kept so an old route to it still has a name.
  tools: { title: 'Tools', symbol: 'globe', summary: 'Where this project’s work happens, and what its agents learn from.' },
  agents: { title: 'Agents', symbol: 'cpu', summary: 'The agents that work in this project, and what each is given.' },
  memory: { title: 'Memory', symbol: 'brain', summary: 'What its agents learned in this project, and what they know in every project.' },
  autonomy: { title: 'What its AI may do', symbol: 'checkmark.shield', summary: 'What its AI does on its own here, what waits for a person, and what is refused.' },
};

export function projectPageInfo(page: ProjectPage): ProjectPageInfo {
  return { page, ...PAGE_INFO[page] };
}

/** One row of a project's sidebar. */
export interface ProjectSidebarRow extends ProjectPageInfo {
  readonly route: Route;
  readonly chosen: boolean;
}

export interface ProjectSidebar {
  readonly back: { readonly title: string; readonly route: Route };
  /** The project's name, standing over its rows as the domain does in Cloudflare's. */
  readonly name: string;
  readonly rows: readonly ProjectSidebarRow[];
}

/** The whole sidebar while a project is open: the way back, its name, and its four pages with the one shown lit. */
export function projectSidebar(project: Pick<ProjectView, 'id' | 'name'>, route: Route): ProjectSidebar {
  return {
    back: { title: BACK_TO_PROJECTS, route: PROJECTS_ROUTE },
    name: project.name,
    rows: PROJECT_PAGE_IDS.map((page) => {
      const to = projectRoute(project.id, page);
      return { ...projectPageInfo(page), route: to, chosen: sameRoute(to, route) };
    }),
  };
}

/** Where a project is changed in Memnox Cloud: the organization's own project page, else the project list there. */
export function cloudProjectLink(project: Pick<ProjectView, 'scope' | 'organization'>): string {
  const shared = sharedBy(project);
  return shared === undefined ? `${MEMNOX_CLOUD}/projects` : `${MEMNOX_CLOUD}/projects/${encodeURIComponent(shared.id)}`;
}

/** Whether this computer may change the project, which only its own projects allow; the organization's is read only. */
export function editableHere(project: Pick<ProjectView, 'scope' | 'organization'>): boolean {
  return sharedBy(project) === undefined;
}

/** The one line under a project's name: its own description where the organization wrote one, else what it is busy with. */
export function projectDescription(project: Pick<ProjectView, 'scope' | 'organization' | 'openMissions'>): string | undefined {
  const written = sharedBy(project)?.description?.trim();
  if (written !== undefined && written !== '') return written;
  const mission = project.openMissions[0]?.statement.trim();
  return mission === undefined || mission === '' ? undefined : `Working on ${mission}`;
}

// The Tools page below is left off for now, and kept whole for when it returns.

/** The shelves the Tools page sorts a project's tools onto, in the order its rail lists them. */
export type ToolCategory = 'files' | 'channels' | 'meetings' | 'tickets' | 'repositories' | 'servers' | 'apps';

export const TOOL_CATEGORIES: readonly { id: ToolCategory; title: string }[] = [
  { id: 'files', title: 'Files' },
  { id: 'channels', title: 'Channels' },
  { id: 'meetings', title: 'Meetings' },
  { id: 'tickets', title: 'Tickets' },
  { id: 'repositories', title: 'Repositories' },
  { id: 'servers', title: 'Servers' },
  { id: 'apps', title: 'Other apps' },
];

/** Which shelf an app or a server belongs on, read off its name, so a server called slack sits with the channels. */
const CATEGORY_WORDS: readonly [ToolCategory, RegExp][] = [
  ['channels', /slack|discord|teams|mattermost|telegram|whatsapp|chat/i],
  ['meetings', /zoom|meet|calendar|webex|gong|fireflies|otter|granola/i],
  ['tickets', /linear|jira|asana|clickup|trello|monday|shortcut|zendesk|intercom|height/i],
  ['repositories', /github|gitlab|bitbucket/i],
  ['files', /notion|docs|drive|dropbox|confluence|box|sharepoint|onedrive|obsidian|sheets|figma/i],
];

export function toolCategory(name: string, otherwise: ToolCategory): ToolCategory {
  return CATEGORY_WORDS.find(([, words]) => words.test(name))?.[0] ?? otherwise;
}

/** What a card's button does: add a server this computer has to the project, or go connect another app. */
export type ToolAction = { readonly kind: 'add-server'; readonly server: string } | { readonly kind: 'connect' };

/** One card on the Tools page: a place the project's work lives, or one it could add. */
export interface ProjectToolCard {
  readonly id: string;
  readonly category: ToolCategory;
  readonly name: string;
  /** What it is, in a word or two: "Server", "Instructions", "Repository", "App". */
  readonly what: string;
  /** What is linked, or what adding it would do. */
  readonly line: string;
  /** Linked to the project now; false on a card that offers to add something. */
  readonly linked: boolean;
  /** False where the project names it and this computer lacks it. */
  readonly ready: boolean;
  readonly action?: ToolAction;
}

/** What the Tools page reads besides the project: the servers set up here and the apps connected as the person. */
export interface ToolSources {
  readonly hub: readonly string[];
  readonly connections: readonly Pick<ToolConnection, 'toolkit' | 'connected' | 'local'>[];
}

/**
 * Channels, meetings and tickets are a team's tools, linked to a project in Memnox Cloud, so their empty shelves stay
 * off the page for now; they come back once user feedback says how a team wants them here.
 */
export const TEAM_TOOLS_SHOWN = false;

const TEAM_SHELVES: readonly ToolCategory[] = ['channels', 'meetings', 'tickets'];

/** An empty shelf offers the apps people usually keep there, so a project that is not code still knows where to start. */
interface SuggestedShelf {
  readonly category: ToolCategory;
  readonly name: string;
  readonly line: string;
}

const SUGGESTED_SHELVES: readonly SuggestedShelf[] = ([
  { category: 'channels', name: 'Add a channel', line: 'Slack, Microsoft Teams or Discord, where the project is talked about' },
  { category: 'files', name: 'Add documents', line: 'Notion, Google Drive or Confluence, where its plans and notes live' },
  { category: 'meetings', name: 'Add meetings', line: 'Zoom, Google Meet or a calendar, where its decisions are made' },
  { category: 'tickets', name: 'Add tickets', line: 'Linear, Jira or Asana, where its work is tracked' },
  { category: 'apps', name: 'Add an app', line: 'Tools its AI can reach and act in, such as Linear, a database or a design tool' },
] satisfies SuggestedShelf[]).filter((shelf) => TEAM_TOOLS_SHOWN || !TEAM_SHELVES.includes(shelf.category));

/** The shelves an app suggestion stands in for, since a server already linked is an app as much as a connected one. */
const APP_SHELVES: readonly ToolCategory[] = ['apps', 'servers'];

/**
 * Every tool of the project as a card. What it has comes first: its servers, the organization's, its instruction
 * files, the apps connected as the person, and its repository, which is one tool among the rest. Then what it could
 * add: each server set up here and not in it yet, on a project this computer may change, and an empty shelf's suggestion.
 */
export function projectToolCards(project: Pick<ProjectView, 'path' | 'servers' | 'instructions' | 'scope' | 'organization'>, sources: ToolSources = { hub: [], connections: [] }): ProjectToolCard[] {
  const shared = sharedBy(project);
  const editable = shared === undefined;
  const own = project.servers.map(
    (server): ProjectToolCard => ({
      id: `server:${server.name}`,
      category: toolCategory(server.name, 'servers'),
      name: server.name,
      what: 'Server',
      line: server.inHub ? `Linked, reached by ${counted(server.agents.length, 'agent', 'agents')} here` : 'Linked, and not set up on this computer yet',
      linked: true,
      ready: server.inHub,
    }),
  );
  const handed = (shared?.servers ?? [])
    .filter((name) => !project.servers.some((server) => server.name === name))
    .map((name): ProjectToolCard => ({ id: `server:${name}`, category: toolCategory(name, 'servers'), name, what: 'Server', line: 'Linked by your organization', linked: true, ready: true }));
  const documents = project.instructions
    .filter((each) => each.source)
    .map((each): ProjectToolCard => ({ id: `file:${each.path}`, category: 'files', name: each.path, what: 'Instructions', line: each.present ? 'Linked, read by its AI' : 'Linked, and missing from its folder', linked: true, ready: each.present }));
  const apps = sources.connections
    .filter((each) => each.connected)
    .map((each): ProjectToolCard => ({
      id: `app:${each.toolkit}`,
      category: toolCategory(each.toolkit, 'apps'),
      name: toolkitName(each.toolkit),
      what: 'App',
      line: each.local === true ? 'On this computer, so its AI reaches it here' : 'Connected as you, so its AI reaches it here',
      linked: true,
      ready: true,
    }));
  const repository = shared?.repository.trim() || project.path.trim();
  const code: ProjectToolCard[] =
    repository === '' ? [] : [{ id: `repository:${repository}`, category: 'repositories', name: repository, what: 'Repository', line: shared === undefined ? 'Linked, its folder on this computer' : 'Linked by your organization', linked: true, ready: true }];
  const has = [...own, ...handed, ...documents, ...apps, ...code];
  const addable = editable
    ? toolsToAdd(project, sources.hub).map(
        (name): ProjectToolCard => ({ id: `add:${name}`, category: toolCategory(name, 'servers'), name, what: 'Server', line: 'Set up on this computer, not in this project yet', linked: false, ready: true, action: { kind: 'add-server', server: name } }),
      )
    : [];
  const shelves = SUGGESTED_SHELVES.filter((shelf) => {
    const covers = shelf.category === 'apps' ? APP_SHELVES : [shelf.category];
    return ![...has, ...addable].some((card) => covers.includes(card.category));
  }).map(
    (shelf): ProjectToolCard => ({ id: `connect:${shelf.category}`, category: shelf.category, name: shelf.name, what: 'App', line: shelf.line, linked: false, ready: true, action: { kind: 'connect' } }),
  );
  return [...has, ...addable, ...shelves];
}

/** How many tools the project has, which is what the checklist's first step reads; the repository alone does not count. */
export function linkedToolCount(cards: readonly ProjectToolCard[]): number {
  return cards.filter((card) => card.linked && card.category !== 'repositories').length;
}

/** The rail's rows for the cards, a shelf nothing sits on left out. */
export function toolCategoryCounts(cards: readonly ProjectToolCard[]): CategoryCount[] {
  return categoryCounts(cards, (card) => card.category, TOOL_CATEGORIES);
}

/** The cards a shelf and a search leave on screen, in their order. */
export function shownToolCards(cards: readonly ProjectToolCard[], category: string, query: string): ProjectToolCard[] {
  const words = searchWords(query);
  return cards.filter((card) => (category === ALL_CATEGORIES || card.category === category) && matchesSearch(words, `${card.name} ${card.what} ${card.line}`));
}

/** The tools a project could add from those this computer already has, in the order the hub lists them. */
export function toolsToAdd(project: Pick<ProjectView, 'servers'>, hub: readonly string[]): string[] {
  return hub.filter((name) => !project.servers.some((server) => server.name === name));
}

/** What a project remembers: its own facts, matched by its folder or its name, the newest first. */
export function projectMemory<T extends Pick<MemoryItemView, 'scope' | 'project' | 'createdAt'>>(items: readonly T[], project: Pick<ProjectView, 'path' | 'name'>): T[] {
  const folder = trimmedPath(project.path);
  const mine = items.filter((item) => item.scope === 'project' && item.project !== undefined && (trimmedPath(item.project) === folder || item.project === project.name));
  return [...mine].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/** How many of what it learned the Overview shows before the Memory page holds the rest. */
export const LEARNED_SHOWN = 3;

function trimmedPath(path: string): string {
  return path.replace(/\\/g, '/').replace(/\/+$/, '');
}

export type ReadyStepId = 'tools' | 'autonomy';

/** One step of the Overview's checklist while the project is still empty, and the page that does it. */
export interface ReadyStep {
  readonly id: ReadyStepId;
  readonly title: string;
  readonly done: boolean;
  readonly page: ProjectPage;
}

/** What the checklist reads: how many tools and rules of its own a project has. */
export interface ReadyCounts {
  readonly tools: number;
  readonly rules: number;
}

/** The short Get it ready checklist, each step done once the project has what it asks for. Adding tools is left off for now with the Tools page. */
export function readySteps(counts: ReadyCounts): ReadyStep[] {
  return [
    { id: 'autonomy', title: 'Choose what its AI may do', done: counts.rules > 0, page: 'autonomy' },
  ];
}

/** Whether the checklist still shows, which it does while a step is still to do. */
export function showReady(counts: ReadyCounts): boolean {
  return readySteps(counts).some((step) => !step.done);
}

/** "2 of 3 done", said beside the checklist's heading. */
export function readyLine(counts: ReadyCounts): string {
  const steps = readySteps(counts);
  return `${steps.filter((step) => step.done).length} of ${steps.length} done`;
}

/** The project's place in the window's header, as Cloudflare's breadcrumb says a domain and its page. */
export function projectCrumbs(project: Pick<ProjectView, 'name'>, page: ProjectPage): readonly string[] {
  return ['Projects', project.name, PAGE_INFO[page].title];
}

/** One AI agent as the Agents page shows it: its name, and what the project gives it or that it only ran here. */
export interface AgentOnProject {
  readonly kind: string;
  readonly name: string;
  readonly line: string;
  /** Whether it ran a session here, said beside an agent the project names. */
  readonly seen: boolean;
}

/** The agents the project names, then any seen working in it that it does not name. */
export interface ProjectAgents {
  readonly given: readonly AgentOnProject[];
  readonly seenOnly: readonly AgentOnProject[];
}

/**
 * The agents on the Agents page: each one the project names with the skills and servers it has of them, then each
 * seen working here that the project names nowhere. Only this computer's agents, since the desktop is one person's.
 */
export function projectAgents(project: Pick<ProjectView, 'agents' | 'agentsSeen' | 'skills' | 'servers'>, agentNames: Readonly<Record<string, string>> = {}): ProjectAgents {
  const nameOf = (kind: string) => agentNames[kind] ?? agentLabel(kind);
  const given = project.agents.map((kind): AgentOnProject => {
    const skills = project.skills.filter((each) => each.agents.includes(kind)).length;
    const servers = project.servers.filter((each) => each.agents.includes(kind)).length;
    return { kind, name: nameOf(kind), line: `${counted(skills, 'skill', 'skills')}, ${counted(servers, 'server', 'servers')}`, seen: project.agentsSeen.includes(kind) };
  });
  const seenOnly = project.agentsSeen
    .filter((kind) => !project.agents.includes(kind))
    .map((kind): AgentOnProject => ({ kind, name: nameOf(kind), line: 'Ran a session here, and the project gives it nothing', seen: true }));
  return { given, seenOnly };
}

/**
 * Whether the project's pages show its people and what Memnox Cloud adds, which only a computer joined to a workspace
 * or a project the organization shares has; the desktop otherwise belongs to one person.
 */
export function showsTeam(project: Pick<ProjectView, 'scope' | 'organization'>, joined: boolean): boolean {
  return joined || sharedBy(project) !== undefined;
}

/** The Overview's heading for who works on it, as Memnox Cloud's Overview names the same tile. */
export const TEAM_TITLE = 'People and agents';

/** Said on Tools once this computer is joined to a workspace, for the team's tools only the cloud links. */
export const CLOUD_TOOLS_LINE = 'Channels, meetings and tickets are linked to a project in Memnox Cloud.';

export const CAN_USE_TITLE = 'What its AI can use';
export const CAN_USE_NOTE = 'The AI agents on this project, what they know how to do, and the apps they can reach.';
/** How many names a part shows before the rest are a count. */
export const CAN_USE_SHOWN = 3;

export type CanUseKind = 'agents' | 'skills' | 'apps';

/** One part of What its AI can use, with what the word means where it has nothing, so nobody needs to know what a skill is. */
export interface CanUsePart {
  readonly kind: CanUseKind;
  readonly title: string;
  readonly names: readonly string[];
  /** Said in place of the names while there are none. */
  readonly empty: string;
  /** What the word means, said under an empty part. */
  readonly what: string;
  /** Agents are named rather than counted, as the cloud's card leaves their count off. */
  readonly counted: boolean;
  /** Where the whole of it is: a page of the project, or a page every project shares. */
  readonly target: CanUseTarget;
}

/** Where a part of What its AI can use opens: one of the project's pages, or a page every project shares. */
export type CanUseTarget = { readonly kind: 'page'; readonly page: ProjectPage } | { readonly kind: 'shared'; readonly row: SharedRow };

/**
 * What its AI can use, as Memnox Cloud's Overview says it: its agents, its skills and its apps. Alone on this computer
 * nothing speaks of people or a team; joined, the words are the cloud's own.
 */
export function canUse(project: Pick<ProjectView, 'agents' | 'skills' | 'servers' | 'scope' | 'organization'>, joined: boolean, agentNames: Readonly<Record<string, string>> = {}): CanUsePart[] {
  const team = showsTeam(project, joined);
  const shared = sharedBy(project);
  const skills = [...new Set([...project.skills.map((each) => each.name), ...(shared?.skills ?? [])])];
  const apps = [...new Set([...project.servers.map((each) => each.name), ...(shared?.servers ?? [])])];
  return [
    {
      kind: 'agents',
      title: 'AI agents',
      names: project.agents.map((kind) => agentNames[kind] ?? agentLabel(kind)),
      empty: team ? 'Any AI agent its people use' : 'Any AI agent you use',
      what: 'Such as Claude Code, Cursor or Codex.',
      counted: false,
      target: { kind: 'page', page: 'agents' },
    },
    {
      kind: 'skills',
      title: 'Skills',
      names: skills,
      empty: 'None yet.',
      what: team
        ? 'Written know how its AI follows, such as how your team reviews work or writes an update.'
        : 'Written know how its AI follows, such as how you review work or write an update.',
      counted: true,
      // The shared My Skills, which narrows to the project the switcher holds, as on the Mac.
      target: { kind: 'shared', row: 'skills' },
    },
    { kind: 'apps', title: 'Apps', names: apps, empty: 'None yet.', what: 'Tools its AI can reach and act in, such as Linear, a database or a design tool.', counted: true, target: { kind: 'shared', row: 'connectors' } },
  ];
}

/** "and 2 more", said under the names a part shows, or undefined when every name is shown. */
export function moreLine(part: Pick<CanUsePart, 'names'>): string | undefined {
  const rest = part.names.length - CAN_USE_SHOWN;
  return rest > 0 ? `and ${rest} more` : undefined;
}

export const SHARE_TITLE = 'Share with your team';

/** Said under Your team: who shares the project, else that it is still only this person's. */
export function teamLine(project: Pick<ProjectView, 'scope' | 'organization'>): string {
  const shared = sharedBy(project);
  return shared === undefined
    ? 'Only you work in this project. Share it in Memnox Cloud and your team’s agents work in it under the same rules as yours.'
    : `Your organization shares this project as ${shared.name}, so the people on it and their agents work under the same rules. Who is on it is changed in Memnox Cloud.`;
}

/** Why a new name cannot be saved, or undefined when it can. */
export function renameProblem(name: string, project: Pick<ProjectView, 'name' | 'scope' | 'organization'>): string | undefined {
  if (!editableHere(project)) return 'Your organization names this project, so it is renamed in Memnox Cloud.';
  if (name.trim() === '') return 'Give it a name.';
  if (name.trim() === project.name) return 'That is already its name.';
  return undefined;
}

/** The manifest a rename writes: everything the project shows now, under its new name. */
export function renamedDraft(project: Parameters<typeof draftOf>[0], name: string): ProjectDraft {
  return { ...draftOf(project), name: name.trim() };
}
