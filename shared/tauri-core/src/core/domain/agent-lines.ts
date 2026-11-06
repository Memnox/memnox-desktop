import type { AgentAction, AgentView } from '@memnox/core/wire';
import { ago, shortPath } from './session-text';

/** Which agents the Agents page shows, as the Mac's `AgentFilter`: all of them, the ones running, or one standing. */
export type AgentFilter = 'all' | 'running' | 'unprotected' | 'paused';

export const AGENT_FILTERS: readonly AgentFilter[] = ['all', 'running', 'unprotected', 'paused'];

export const AGENT_FILTER_TITLES: Record<AgentFilter, string> = {
  all: 'All',
  running: 'Running',
  unprotected: 'Not protected',
  paused: 'Paused',
};

type Standing = Pick<AgentView, 'kind' | 'name' | 'status' | 'seam' | 'sessions' | 'today' | 'recent' | 'skills' | 'mcpServers'>;

export function admits(filter: AgentFilter, agent: Pick<AgentView, 'status' | 'sessions'>): boolean {
  switch (filter) {
    case 'all':
      return true;
    case 'running':
      return agent.sessions.running > 0;
    case 'unprotected':
      return agent.status === 'unprotected';
    case 'paused':
      return agent.status === 'paused';
  }
}

/** The one press a card leads with: Protect where the agent runs outside Memnox, else pause or resume it. */
export type AgentPress = 'protect' | 'pause' | 'resume';

/** One small labelled number on an agent's card, amber for what waited on a person and red for what was refused. */
export interface AgentFigure {
  readonly label: string;
  readonly value: number;
  readonly tone: 'good' | 'quiet' | 'attention' | 'bad';
}

/** What a Protect press came to for the agents it was pressed for, read from the cards the runtime drew after it. */
export interface ProtectResult {
  readonly kinds: readonly string[];
  readonly line: string;
  /** True when every one of them is protected now. */
  readonly held: boolean;
  /** The daemon answering predates the app, so a restart of the service is the step that helps. */
  readonly restartService: boolean;
  /** When the cards were read after the press, so the line says how fresh it is. */
  readonly at?: number;
}

/** Said on a card whose agent has no session running and did nothing today. */
export const NOTHING_TODAY = 'Nothing today';
/** The strip's reminder under the names, until a press has something newer to say. */
export const OUTSIDE_MEMNOX = 'Outside Memnox, nothing an agent tries is ruled on.';
/** The recent actions a card lists; the Activity page holds the rest. */
export const RECENT_SHOWN = 3;
/** The skills a card names as chips before it counts the rest. */
export const SKILL_CHIPS = 3;

const ORDER: readonly AgentView['status'][] = ['paused', 'unprotected', 'protected', 'dormant'];

/** The ones needing a decision first, agents of one standing in the runtime's order. */
export function sortedAgents<A extends Pick<AgentView, 'status'>>(agents: readonly A[]): A[] {
  const rank = (agent: A) => {
    const index = ORDER.indexOf(agent.status);
    return index === -1 ? ORDER.length : index;
  };
  return agents
    .map((agent, index) => ({ agent, index }))
    .sort((a, b) => rank(a.agent) - rank(b.agent) || a.index - b.index)
    .map((each) => each.agent);
}

/** "6 agents, 5 protected, 1 running" */
export function agentsSummary(agents: readonly Pick<AgentView, 'status' | 'sessions'>[]): string {
  const protectedCount = agents.filter((agent) => agent.status === 'protected').length;
  const running = agents.filter((agent) => admits('running', agent)).length;
  return `${counted(agents.length, 'agent', 'agents')}, ${protectedCount} protected, ${running} running`;
}

export function shownAgents<A extends Pick<AgentView, 'status' | 'sessions'>>(agents: readonly A[], filter: AgentFilter): A[] {
  return sortedAgents(agents.filter((agent) => admits(filter, agent)));
}

export function filterCount(agents: readonly Pick<AgentView, 'status' | 'sessions'>[], filter: AgentFilter): number {
  return agents.filter((agent) => admits(filter, agent)).length;
}

/** All, Running and Paused always, so their counts read even at nought, and Not protected only while some agent is. */
export function agentFilters(agents: readonly Pick<AgentView, 'status' | 'sessions'>[]): AgentFilter[] {
  return AGENT_FILTERS.filter((filter) => filter !== 'unprotected' || filterCount(agents, filter) > 0);
}

export function agentPress(agent: Pick<AgentView, 'status'>): AgentPress {
  if (agent.status === 'unprotected') return 'protect';
  if (agent.status === 'paused') return 'resume';
  return 'pause';
}

/** The standing in a word and its tone, as the card's pill says it. */
export function statusWord(status: string): { word: string; tone: 'good' | 'attention' | 'quiet' | 'bad' } {
  switch (status) {
    case 'protected':
      return { word: 'Protected', tone: 'good' };
    case 'unprotected':
      return { word: 'Not protected', tone: 'attention' };
    case 'dormant':
      return { word: 'Dormant', tone: 'quiet' };
    case 'paused':
      return { word: 'Paused', tone: 'bad' };
    default:
      return { word: status, tone: 'quiet' };
  }
}

/** The quiet line under a card's numbers: when it last did anything, and how many skills and MCP servers it has. */
export function reachLine(agent: Pick<AgentView, 'recent' | 'skills' | 'mcpServers'>, now: number): string {
  const when = ago(agent.recent[0]?.at, now);
  const seen = when === undefined ? 'No activity seen yet' : `Last active ${when}`;
  return `${seen} · ${counted(agent.skills.length, 'skill', 'skills')} · ${counted(agent.mcpServers.length, 'MCP server', 'MCP servers')}`;
}

/** The first few skills by name and a count of the rest, so a card keeps one line of chips. */
export function skillChips(names: readonly string[] | undefined, limit: number): { shown: string[]; more: number } {
  const all = names ?? [];
  return { shown: all.slice(0, limit), more: Math.max(0, all.length - limit) };
}

/** Only the numbers that say something: sessions running and today's actions, asks and refusals above nought. */
export function agentFigures(agent: Pick<AgentView, 'sessions' | 'today'>): AgentFigure[] {
  const all: AgentFigure[] = [
    { label: 'Running', value: agent.sessions.running, tone: 'good' },
    { label: 'Today', value: agent.today.actions, tone: 'quiet' },
    { label: 'Asked', value: agent.today.asked, tone: 'attention' },
    { label: 'Refused', value: agent.today.refused, tone: 'bad' },
  ];
  return all.filter((figure) => figure.value > 0);
}

/** "Claude Desktop is not protected", or undefined while every agent is. */
export function needsProtecting(agents: readonly Pick<AgentView, 'status' | 'name'>[]): string | undefined {
  const names = agents.filter((agent) => agent.status === 'unprotected').map((agent) => agent.name);
  if (names.length === 0) return undefined;
  return `${listed(names)} ${names.length === 1 ? 'is' : 'are'} not protected`;
}

export function unprotectedKinds(agents: readonly Pick<AgentView, 'status' | 'kind'>[]): string[] {
  return agents.filter((agent) => agent.status === 'unprotected').map((agent) => agent.kind);
}

/** No card says how Memnox holds its agent, which a runtime that knows seams always says for one with a hook. */
export function runtimePredatesSeams(agents: readonly Pick<AgentView, 'seam'>[]): boolean {
  return agents.length > 0 && agents.every((agent) => agent.seam === undefined);
}

/**
 * What a Protect press came to, from the cards read after it: the reason it failed, that they are protected and
 * whether an app must be opened again to take its servers up, or what still keeps one outside.
 */
export function afterProtect(kinds: readonly string[], agents: readonly Standing[], failed: string | undefined, options: { restarted?: boolean; at?: number } = {}): ProtectResult {
  const at = options.at === undefined ? {} : { at: options.at };
  if (failed !== undefined) return { kinds, line: failed, held: false, restartService: false, ...at };
  const asked = agents.filter((agent) => kinds.includes(agent.kind));
  const left = asked.filter((agent) => agent.status === 'unprotected');
  const first = left[0];
  if (first === undefined) return { kinds, line: protectedLine(asked), held: true, restartService: false, ...at };
  const names = left.map((agent) => agent.name);
  const one = names.length === 1;
  if (runtimePredatesSeams(agents)) {
    const line = options.restarted === true
      ? `The Memnox service restarted but still runs a runtime older than this app, so it counts ${listed(names)} as outside. Update the runtime, then restart the service.`
      : `The Memnox service on this computer is older than this app, so it cannot see that ${listed(names)} ${one ? 'is' : 'are'} held. Restart it to run the newer runtime.`;
    return { kinds, line, held: false, restartService: true, ...at };
  }
  let line: string;
  if (first.seam === 'servers') {
    line = `${listed(names)} still ${one ? 'starts' : 'start'} a server outside Memnox, which setup leaves alone when it cannot find memnox-mcp-proxy. In a terminal: memnox mcp wrap`;
  } else if (first.seam === 'hook') {
    line = `${listed(names)} ${one ? 'is' : 'are'} still not protected because ${one ? 'its' : 'their'} hook did not go in. In a terminal: memnox setup`;
  } else {
    line = `Memnox has no way into ${listed(names)} yet, so Protect cannot hold ${one ? 'it' : 'them'}.`;
  }
  return { kinds, line, held: false, restartService: false, ...at };
}

/** "Claude Desktop is protected. Quit and open it again so its servers start through Memnox." */
function protectedLine(agents: readonly Standing[]): string {
  const names = agents.map((agent) => agent.name);
  if (names.length === 0) return 'Your agents are protected.';
  const done = `${listed(names)} ${names.length === 1 ? 'is' : 'are'} protected.`;
  // An agent held only through its servers reads its config when it opens, so the change waits for a restart.
  const reopen = agents.filter((agent) => agent.seam === 'servers').map((agent) => agent.name);
  if (reopen.length === 0) return done;
  return `${done} Quit and open ${listed(reopen)} again so ${reopen.length === 1 ? 'its' : 'their'} servers start through Memnox.`;
}

/** A recent action's target as a person names it, the path's last parts, or undefined where it had none. */
export function actionTarget(action: Pick<AgentAction, 'target'>): string | undefined {
  const target = action.target?.trim();
  if (target === undefined || target === '') return undefined;
  return target.includes('/') ? shortPath(target) : target;
}

/** Said where a filter leaves no agent to show. */
export function noneShown(filter: AgentFilter): string {
  switch (filter) {
    case 'all':
      return 'No agents found yet.';
    case 'running':
      return 'No agent has a session running right now.';
    case 'unprotected':
      return 'Every agent here is protected.';
    case 'paused':
      return 'No agent is paused.';
  }
}

/** "A", "A and B", "A, B and C". */
function listed(names: readonly string[]): string {
  if (names.length <= 1) return names.join('');
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1] ?? ''}`;
}

function counted(count: number, one: string, many: string): string {
  return count === 1 ? `1 ${one}` : `${count} ${many}`;
}
