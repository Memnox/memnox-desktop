import type { AgentConnection, CapabilityLevel, CapabilityLevels } from './agent-wire';
import { ENFORCEMENT_SEAMS } from './agent-wire';

/**
 * The five capability levels in plain words on every screen, with the technical names kept for Advanced. Every level
 * is the daemon's or the cloud's; nothing here works one out, so a screen can only say less than it was told.
 * Mirrors `CapabilityLevelLines.swift`.
 */

export const LEVEL_WORDS: Record<CapabilityLevel, string> = {
  enforced: 'Memnox stops this',
  mediated: 'Memnox checks this',
  advisory: 'The agent asks Memnox',
  observed: 'Memnox only sees this',
  none: 'Outside Memnox',
};

/** The six capabilities beside enforcement, as a person reads them. */
const CAPABILITY_TITLES = {
  context: 'What it knows',
  instructions: 'Its instructions',
  tools: 'Its tools',
  activity: 'What it did',
  coordination: 'Working beside others',
  approval: 'Asking you first',
} as const;

type GeneralCapability = keyof typeof CAPABILITY_TITLES;

const SEAM_TITLES: Record<string, string> = {
  shell: 'Commands',
  filesystem: 'Files',
  git: 'Git',
  network: 'The network',
  browser: 'The browser',
  mcp: 'MCP tools',
  // Memnox Cloud states enforcement as one level for everything an agent runs.
  everything: 'Everything it runs',
};

/** One line of the strip: its title, its level, and its technical words for Advanced. */
export interface LevelRow {
  key: string;
  title: string;
  level: CapabilityLevel;
  plain: string;
  technical: string;
}

function row(key: string, title: string, level: CapabilityLevel): LevelRow {
  return { key, title, level, plain: LEVEL_WORDS[level] ?? LEVEL_WORDS.none, technical: `${key}: ${level}` };
}

export function levelRows(levels: CapabilityLevels): LevelRow[] {
  return (Object.keys(CAPABILITY_TITLES) as GeneralCapability[]).map((key) => row(key, CAPABILITY_TITLES[key], levels[key]));
}

/** Enforcement by seam, in the runtime's order, then any seam this app does not know yet by name. */
export function seamRows(levels: CapabilityLevels): LevelRow[] {
  const known: readonly string[] = ENFORCEMENT_SEAMS;
  const enforcement: Record<string, CapabilityLevel> = levels.enforcement;
  const order = [...known, ...Object.keys(enforcement).filter((seam) => !known.includes(seam)).sort()];
  return order.flatMap((seam) => {
    const level = enforcement[seam];
    return level === undefined ? [] : [row(`enforcement.${seam}`, SEAM_TITLES[seam] ?? seam, level)];
  });
}

/** Weakest first, so the lower index is the one a summary must not hide. */
const ORDER: readonly CapabilityLevel[] = ['none', 'observed', 'advisory', 'mediated', 'enforced'];

export function weaker(one: CapabilityLevel, two: CapabilityLevel): CapabilityLevel {
  return Math.max(ORDER.indexOf(one), 0) <= Math.max(ORDER.indexOf(two), 0) ? one : two;
}

/** The one level a pill wears: the weakest of the six, so a pill never says more than every line of the strip. */
export function headlineLevel(levels: CapabilityLevels): CapabilityLevel {
  return levelRows(levels).reduce<CapabilityLevel>((least, each) => weaker(least, each.level), 'enforced');
}

/** A connection's pill: its own levels, or, from a runtime that sends none, what its mediation says. */
export function connectionLevel(connection: AgentConnection): CapabilityLevel {
  if (connection.levels !== undefined) return headlineLevel(connection.levels);
  if (connection.mediation === 'interposed') return 'mediated';
  if (connection.mediation === 'advisory') return 'advisory';
  return 'observed';
}

const CONNECTION_WORDS: Record<string, string> = {
  runtime_hook: 'Its own hook on this computer',
  runtime_mcp_proxy: 'Its MCP servers through Memnox',
  guard: 'The Memnox guard in its code',
  gateway: 'The Memnox gateway',
  mcp: 'It talks to Memnox over MCP',
  observed: 'Seen here, nothing in front of it',
};

const STATUS_WORDS: Record<string, string> = { live: 'Working now', idle: 'Idle', gone: 'Not found any more' };

/** How Memnox reaches the agent, in plain words. */
export function connectionKindLine(connection: AgentConnection): string {
  return CONNECTION_WORDS[connection.kind] ?? connection.kind;
}

export function connectionStatusLine(connection: AgentConnection): string {
  return STATUS_WORDS[connection.status] ?? connection.status;
}

/** Green where Memnox stops or checks it, amber where it only asks or sees, red where it is outside. */
export function levelTone(level: CapabilityLevel): 'good' | 'attention' | 'bad' {
  if (level === 'enforced' || level === 'mediated') return 'good';
  if (level === 'advisory' || level === 'observed') return 'attention';
  return 'bad';
}
