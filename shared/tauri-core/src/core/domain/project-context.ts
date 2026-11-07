import type { MemoryItemView, ProjectView, SessionCard } from '@memnox/core/wire';
import { SIDEBAR_ROWS, shownPages, type Route, type SidebarRow, type Supports } from './destinations';
import { agentLabel } from './mcp-hub-lines';
import { counted, sharedBy } from './project-lines';
import { projectRoute, type ProjectPlace } from './destinations';
import { ago, cardStatus, repositoryName } from './session-text';
import { isActive } from './session-status';

/**
 * The two contexts a person with several projects moves between: what belongs to one project, and what is shared with
 * every project on this computer. It only reads what the daemon scopes; anything carrying no project is shared.
 * Mirrors the Mac's `ProjectContext.swift`.
 */

/** Whether something on a project's page belongs to that project alone or is shared with every project. */
export type ItemReach = 'only-here' | 'every-project';

export const REACH_WORD: Readonly<Record<ItemReach, string>> = {
  'only-here': 'Only here',
  'every-project': 'Every project',
};

/** What the badge says to a screen reader and on hover. */
export const REACH_HINT: Readonly<Record<ItemReach, string>> = {
  'only-here': 'Belongs to this project alone',
  'every-project': 'Shared with every project, and changed on its own page',
};

// Shared with every project

export const SHARED_TITLE = 'Shared with every project';
export const SHARED_NOTE = 'Set once for every project on this computer, and changed on its own page.';
/** The shared group is left off a project's sidebar for now, since each item's badge already says where it is shared. */
export const SHARED_SHOWN = false;

/** The shared pages, by the sidebar row that opens each. */
export type SharedRow = 'protection' | 'skills' | 'servers' | 'connectors' | 'memory' | 'agents';

/** The rows of the shared group, in the order the Mac lists them. */
export const SHARED_ROWS: readonly SharedRow[] = ['protection', 'skills', 'servers', 'connectors', 'memory', 'agents'];

const ROW_TITLE: Readonly<Record<SharedRow, string>> = {
  protection: 'Protection settings',
  skills: 'Skills',
  servers: 'MCP servers',
  connectors: 'Connectors',
  memory: 'Memory',
  agents: 'AI agents',
};

/** How much of each shared page applies to one project, each undefined while it is still being read. */
export interface SharedCounts {
  readonly rules?: number;
  readonly skills?: number;
  readonly servers?: number;
  readonly connectors?: number;
  readonly memory?: number;
  readonly agents?: number;
}

/** One link in the shared group: the machine wide page it opens and how much of it applies to this project. */
export interface SharedLink {
  readonly row: SharedRow;
  readonly title: string;
  readonly symbol: SidebarRow['symbol'];
  readonly count?: number;
  /** Said on hover and to a screen reader: what of it applies here. */
  readonly hint: string;
  readonly route: Route;
}

const COUNT_OF: Readonly<Record<SharedRow, keyof SharedCounts>> = {
  protection: 'rules',
  skills: 'skills',
  servers: 'servers',
  connectors: 'connectors',
  memory: 'memory',
  agents: 'agents',
};

/** The shared group at the foot of a project's sidebar: only the pages the daemon answers, so no link leads nowhere. */
export function shared(counts: SharedCounts, supports: Supports): SharedLink[] {
  return SHARED_ROWS.flatMap((id) => {
    const row = SIDEBAR_ROWS.find((each) => each.title === ROW_TITLE[id]);
    const page = row === undefined ? undefined : shownPages(row, supports)[0];
    if (row === undefined || page === undefined) return [];
    const count = counts[COUNT_OF[id]];
    return [{ row: id, title: row.title, symbol: row.symbol, ...(count === undefined ? {} : { count }), hint: sharedHint(id, count), route: page.route }];
  });
}

function sharedHint(row: SharedRow, count: number | undefined): string {
  if (count === undefined) return `${ROW_TITLE[row]}, shared with every project`;
  switch (row) {
    case 'protection':
      return `${counted(count, 'rule holds', 'rules hold')} here and in every project`;
    case 'skills':
      return `${counted(count, 'skill', 'skills')} its agents carry in every project`;
    case 'servers':
      return `${counted(count, 'server', 'servers')} given to agents in every project`;
    case 'connectors':
      return `${counted(count, 'app', 'apps')} connected as you, reached from every project`;
    case 'memory':
      return `${counted(count, 'fact', 'facts')} known in every project`;
    case 'agents':
      return `${counted(count, 'agent', 'agents')} on this computer, set up once for every project`;
  }
}

// Which items belong where

type Place = Pick<ProjectView, 'id' | 'name' | 'path' | 'scope' | 'organization'>;

/**
 * A skill the daemon wrote into this project's folder is only here; the person's own and the organization's are
 * shared; one written into another project is undefined, since it does not apply here.
 */
export function skillReach(skillScope: string, skillProject: string | undefined, project: Pick<ProjectView, 'path'>): ItemReach | undefined {
  if (skillScope !== 'project') return 'every-project';
  if (skillProject === undefined || skillProject === '') return 'every-project';
  return inside(normalised(skillProject), normalised(project.path)) ? 'only-here' : undefined;
}

/** A server the project's manifest names is only here, unless the hub already gives it to agents everywhere. */
export function serverReach(givenEverywhere: boolean): ItemReach {
  return givenEverywhere ? 'every-project' : 'only-here';
}

/**
 * Memory kept under this project is only here, memory under no project is shared, and memory another project learned
 * is undefined, since it does not apply here.
 */
export function memoryReach(item: Pick<MemoryItemView, 'project'>, project: Place): ItemReach | undefined {
  const owner = ownerKey(item.project);
  if (owner === undefined) return 'every-project';
  return belongs(owner, project) ? 'only-here' : undefined;
}

/** What one project learned, newest first, and what is known in every project because it names none. */
export function projectMemorySplit<T extends Pick<MemoryItemView, 'project' | 'createdAt'>>(items: readonly T[], project: Place): { here: T[]; everywhere: T[] } {
  const here = items.filter((item) => memoryReach(item, project) === 'only-here');
  const everywhere = items.filter((item) => ownerKey(item.project) === undefined);
  return { here: newestFirst(here), everywhere: newestFirst(everywhere) };
}

export const MEMORY_HERE_TITLE = 'What this project learned';
export const MEMORY_EVERYWHERE_TITLE = 'Also known everywhere';
export const MEMORY_EVERYWHERE_NOTE = 'Facts that belong to no one project, so the agents in every project read them.';
export const MEMORY_HERE_EMPTY = 'Nothing learned in this project yet. As its agents work here, what they learn shows here.';
/** How many shared facts the project's Memory page shows before linking to the rest. */
export const EVERYWHERE_SHOWN = 5;

// The shared Memory page's filter

/** The memory page's project filter: everything, what is shared with every project, or what one project learned. */
export type MemoryProjectChoice = { readonly kind: 'all' } | { readonly kind: 'shared' } | { readonly kind: 'project'; readonly id: string };

/** Where the filter is remembered, by the project's id, the shared key, or empty for everything. */
export const MEMORY_CHOICE_KEY = 'memnox.memory.project';
const SHARED_MEMORY_KEY = 'shared';
export const ALL_MEMORY_TITLE = 'All projects';
export const SHARED_MEMORY_TITLE = 'Shared with every project';

/** How the choice is remembered between openings. */
export function choiceKey(choice: MemoryProjectChoice): string {
  switch (choice.kind) {
    case 'all':
      return '';
    case 'shared':
      return SHARED_MEMORY_KEY;
    case 'project':
      return choice.id;
  }
}

export function choiceOfKey(key: string | null | undefined): MemoryProjectChoice {
  if (key === null || key === undefined || key === '') return { kind: 'all' };
  if (key === SHARED_MEMORY_KEY) return { kind: 'shared' };
  return { kind: 'project', id: key };
}

/** The filter's choices: everything, what is shared, then each project, the most recently active first. */
export function memoryChoices<P extends Pick<ProjectView, 'id' | 'name' | 'lastActive'>>(projects: readonly P[]): { choice: MemoryProjectChoice; title: string }[] {
  return [
    { choice: { kind: 'all' }, title: ALL_MEMORY_TITLE },
    { choice: { kind: 'shared' }, title: SHARED_MEMORY_TITLE },
    ...recent(projects).map((project) => ({ choice: { kind: 'project', id: project.id } as const, title: project.name })),
  ];
}

/** The facts the filter leaves on screen; a project that is gone shows everything rather than nothing. */
export function shownMemory<T extends Pick<MemoryItemView, 'project'>>(items: readonly T[], choice: MemoryProjectChoice, projects: readonly Place[]): T[] {
  switch (choice.kind) {
    case 'all':
      return [...items];
    case 'shared':
      return items.filter((item) => ownerKey(item.project) === undefined);
    case 'project': {
      const project = projects.find((each) => each.id === choice.id);
      if (project === undefined) return [...items];
      return items.filter((item) => memoryReach(item, project) === 'only-here');
    }
  }
}

/**
 * Whose a fact is, said beside it: the project's name, Every project for a fact naming none, or the folder's own name
 * for a project this computer has not opened.
 */
export function memoryOwner(item: Pick<MemoryItemView, 'project'>, projects: readonly Place[]): string {
  const owner = ownerKey(item.project);
  if (owner === undefined) return REACH_WORD['every-project'];
  return projects.find((each) => belongs(owner, each))?.name ?? folderName(owner);
}

// The Projects list

/** From how many projects the list offers a search, since a few fit on screen without one. */
export const SEARCH_FROM = 6;
export const SEARCH_PROMPT = 'Find a project';
export const EMPTY_TITLE = 'Keep each piece of work apart';
export const EMPTY_LINE =
  'A project is a folder on this computer where your AI agents work, such as a website, a report or a campaign. Add one and Memnox keeps what its agents learn and may do there apart from your other work.';
export const SUGGESTIONS_TITLE = 'Folders your agents worked in';
export const SUGGESTIONS_NOTE = 'Your agents already worked in these folders. Add one to make it a project.';
export const CHOOSE_TITLE = 'Choose a folder';
export const ADD_TITLE = 'Add';
export const NO_ACTIVITY = 'No activity yet';

/** The projects most recently active first; two equally recent keep the daemon's order. */
export function recent<P extends Pick<ProjectView, 'lastActive'>>(projects: readonly P[]): P[] {
  return projects
    .map((project, offset) => ({ project, offset }))
    .sort((left, right) => {
      const a = left.project.lastActive ?? '';
      const b = right.project.lastActive ?? '';
      if (a === b) return left.offset - right.offset;
      return a > b ? -1 : 1;
    })
    .map((each) => each.project);
}

/** The projects whose name or folder holds every word typed. */
export function matching<P extends Pick<ProjectView, 'name' | 'path'>>(projects: readonly P[], query: string): P[] {
  const words = query.toLowerCase().split(/\s+/).filter((word) => word !== '');
  if (words.length === 0) return [...projects];
  return projects.filter((project) => {
    const text = `${project.name} ${project.path}`.toLowerCase();
    return words.every((word) => text.includes(word));
  });
}

/** Who works in the project now, what waits on the person there, and when anything last happened. */
export interface ProjectPulse {
  /** The kinds of the agents working there now, each once. */
  readonly working: readonly string[];
  readonly waiting: number;
  readonly lastActivity: string;
}

/** "Claude Code working now", "2 agents working now", or undefined while nobody works there. */
export function workingLine(pulse: Pick<ProjectPulse, 'working'>): string | undefined {
  const [first] = pulse.working;
  if (first === undefined) return undefined;
  return pulse.working.length === 1 ? `${agentLabel(first)} working now` : `${pulse.working.length} agents working now`;
}

/** "1 waits on you", or undefined while nothing does. */
export function waitingLine(pulse: Pick<ProjectPulse, 'waiting'>): string | undefined {
  if (pulse.waiting === 0) return undefined;
  return pulse.waiting === 1 ? '1 waits on you' : `${pulse.waiting} wait on you`;
}

type SessionFacts = Pick<SessionCard, 'repository' | 'agent' | 'agentName' | 'lastActive' | 'state' | 'thinking'>;

/**
 * Who works in the project now, what waits on the person there, and its last activity, from the sessions and the held
 * calls already read. A held call names its folder only by name, so that is what it is matched by.
 */
export function pulse(project: Pick<ProjectView, 'name' | 'path' | 'lastActive'>, sessions: readonly SessionFacts[], waitingPlaces: readonly (string | undefined)[], now: number): ProjectPulse {
  const here = sessions.filter((card) => holds(card.repository, project));
  const working: string[] = [];
  for (const card of here) {
    if (!isActive(cardStatus(card as SessionCard))) continue;
    const kind = card.agent ?? card.agentName;
    if (!working.includes(kind)) working.push(kind);
  }
  const waiting = waitingPlaces.filter((place) => named(place, project)).length;
  const moments = [project.lastActive, ...here.map((card) => card.lastActive)].filter((each): each is string => each !== undefined);
  const latest = moments.length === 0 ? undefined : moments.reduce((a, b) => (a > b ? a : b));
  const said = ago(latest, now);
  const lastActivity = working.length > 0 ? 'Active now' : said === undefined ? NO_ACTIVITY : `Active ${said}`;
  return { working, waiting, lastActivity };
}

/** Whether an agent is working in the project now, which lights its dot in the switcher. */
export function live(project: Pick<ProjectView, 'path'>, sessions: readonly SessionFacts[]): boolean {
  return sessions.some((card) => isActive(cardStatus(card as SessionCard)) && holds(card.repository, project));
}

// The switcher

export const SWITCHER_PROMPT = 'Find a project';
export const ALL_PROJECTS_TITLE = 'All projects';
export const SWITCHER_HINT = 'Switch to another project';

/** One project in the sidebar's switcher: its name, its folder, and whether an agent is working there now. */
export interface SwitcherRow {
  readonly id: string;
  readonly name: string;
  readonly folder: string;
  readonly live: boolean;
  readonly current: boolean;
}

/** Every project, most recently active first, narrowed by what was typed, with the one open marked. */
export function switcher(projects: readonly Pick<ProjectView, 'id' | 'name' | 'path' | 'lastActive'>[], sessions: readonly SessionFacts[], current: string | undefined, query: string): SwitcherRow[] {
  return matching(recent(projects), query).map((project) => ({
    id: project.id,
    name: project.name,
    folder: project.path,
    live: live(project, sessions),
    current: project.id === current,
  }));
}

/** Switching keeps the page the person was on, so Memory stays Memory in the next project. */
export function switchRoute(id: string, from: ProjectPlace): Route {
  return projectRoute(id, from.page);
}

// Naming where things happen

/** The project a session's repository sits in, by its name, else the folder's own name. */
export function projectName(repository: string | undefined, projects: readonly Pick<ProjectView, 'name' | 'path'>[]): string | undefined {
  const kept = repositoryName(repository);
  if (kept === undefined) return undefined;
  return projects.find((project) => holds(kept, project))?.name ?? folderName(kept);
}

/** The project a held call's folder name belongs to, else the folder's name as the daemon sent it. */
export function projectNameOfPlace(place: string | undefined, projects: readonly Pick<ProjectView, 'name' | 'path'>[]): string | undefined {
  const kept = repositoryName(place);
  if (kept === undefined) return undefined;
  return projects.find((project) => named(kept, project))?.name ?? kept;
}

/** "In Spring launch", said before what an item on Home or Needs your attention is about. */
export function inLine(name: string | undefined): string | undefined {
  return name === undefined ? undefined : `In ${name}`;
}

// Matching

/** The project's own memory key, which an organization project keeps its memory under. */
const ORGANIZATION_MEMORY_PREFIX = 'org-project:';

function ownerKey(value: string | undefined): string | undefined {
  return value === undefined || value.trim() === '' ? undefined : value;
}

/** Whether a memory item or source's project names this one, by its id, folder, name or organization key. */
export function belongs(value: string, project: Place): boolean {
  const organization = sharedBy(project)?.id;
  const names = [project.id, project.path, project.name, organization].filter((each): each is string => each !== undefined && each !== '');
  if (names.includes(value)) return true;
  if (project.path !== '' && normalised(value) === normalised(project.path)) return true;
  return organization !== undefined && organization !== '' && value === `${ORGANIZATION_MEMORY_PREFIX}${organization}`;
}

/** Whether a session's repository sits inside the project's folder. */
function holds(repository: string | undefined, project: Pick<ProjectView, 'path'>): boolean {
  if (repository === undefined || repository === '' || project.path === '') return false;
  return inside(normalised(repository), normalised(project.path));
}

/** Whether a folder's name is the project's folder or the project itself. */
function named(place: string | undefined, project: Pick<ProjectView, 'name' | 'path'>): boolean {
  if (place === undefined || place === '') return false;
  return place === folderName(project.path) || place === project.name;
}

function inside(folder: string, root: string): boolean {
  return folder === root || folder.startsWith(`${root}/`);
}

function folderName(path: string): string {
  const parts = normalised(path).split('/').filter((part) => part !== '');
  return parts[parts.length - 1] ?? path;
}

function normalised(path: string): string {
  let each = path.replace(/\\/g, '/');
  while (each.length > 1 && each.endsWith('/')) each = each.slice(0, -1);
  return each;
}

function newestFirst<T extends Pick<MemoryItemView, 'createdAt'>>(items: readonly T[]): T[] {
  return [...items].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}
