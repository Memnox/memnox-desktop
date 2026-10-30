import type { CommunityIndexView, IndexEntryView, IndexInstalled, IndexKind } from '@memnox/core/wire';
import { agentLabel } from './mcp-hub-lines';

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** The kind filter on Discover: everything, or one of the two kinds the index lists. */
export type IndexKindFilter = 'all' | IndexKind;

/** What a listing is, in a word a person reads. */
export function indexKindWord(kind: string): string {
  return kind === 'rule_pack' ? 'Rule pack' : 'Skill';
}

/** "By Acme", whether an organization or a member published it. */
export function publisherLine(publisher: IndexEntryView['publisher']): string {
  return `By ${publisher.name}`;
}

/** The agents a listing supports, by name, or that it works with every agent. */
export function supportedAgentsLine(agents: readonly string[]): string {
  if (agents.length === 0) return 'Works with every agent';
  return `For ${listed(agents.map(agentLabel))}`;
}

/** "v1.2.0", or that every version was marked unsafe and nothing can be installed. */
export function latestLine(entry: Pick<IndexEntryView, 'latest' | 'unsafe'>): string {
  if (entry.unsafe || entry.latest === undefined) return 'No safe version to install';
  return `v${entry.latest.version}`;
}

/** A count of versions marked unsafe, or undefined when there are none. Counts, never a score. */
export function yankedLine(yanked: readonly string[]): string | undefined {
  if (yanked.length === 0) return undefined;
  return yanked.length === 1 ? '1 version marked unsafe' : `${yanked.length} versions marked unsafe`;
}

/** Only a version that is not marked unsafe is offered, and only when the listing has one. */
export function canInstall(entry: Pick<IndexEntryView, 'latest' | 'unsafe'>): boolean {
  return !entry.unsafe && entry.latest !== undefined;
}

/** What a skill already in the hub is at, so Install reads as an update rather than a first install. */
export function installedLine(entry: Pick<IndexEntryView, 'installed' | 'kind'>): string | undefined {
  if (entry.installed === undefined || entry.kind !== 'skill') return undefined;
  return `v${entry.installed} in My Skills`;
}

/** Where an install from the index goes next, said under every Install so nobody expects it to be live. */
export function installWaitsLine(kind: string, keyTitle: string): string {
  if (kind === 'rule_pack') return `Installing a rule pack proposes each of its rules, and each waits for your signature with ${keyTitle} on the island.`;
  return 'Installing a skill puts it in My Skills, where it waits for you to accept it before any agent is given it.';
}

/** The categories the listings carry, each once, in order. */
export function categoriesOf(entries: readonly IndexEntryView[]): string[] {
  const named = entries.map((entry) => entry.category).filter((category): category is string => category !== undefined && category !== '');
  return [...new Set(named)].sort((a, b) => a.localeCompare(b));
}

/** The listings in one category, or all of them; the runtime filters words and kind, the category is the window's. */
export function inCategory(entries: readonly IndexEntryView[], category: string | undefined): IndexEntryView[] {
  return category === undefined ? [...entries] : entries.filter((entry) => entry.category === category);
}

/** Where the index was read from and how long ago, or why it is not fresh, in a line. */
export function indexStateLine(view: Pick<CommunityIndexView, 'source' | 'fetchedAt' | 'said' | 'complete'>, now: number): string {
  if (view.said !== undefined && view.said !== '') return view.said;
  const partial = view.complete ? '' : ' It held more than it carries, so some listings are not shown.';
  if (view.fetchedAt === undefined) return `Not read from ${view.source} yet.${partial}`;
  return `Read from ${view.source} ${sinceLine(view.fetchedAt, now)}.${partial}`;
}

/** What an install did, in a line: a skill held for acceptance, or how many rules wait on the island. */
export function indexInstalledLine(installed: Pick<IndexInstalled, 'name' | 'kind' | 'version' | 'proposed' | 'held'>, keyTitle: string): string {
  if (installed.kind === 'rule_pack') {
    const count = installed.proposed.length;
    if (count === 0) return `${installed.name} v${installed.version} held no rule to propose.`;
    const rules = count === 1 ? '1 rule waits' : `${count} rules wait`;
    return `${rules} from ${installed.name} v${installed.version} for your signature with ${keyTitle} on the island.`;
  }
  if (installed.held) return `${installed.name} v${installed.version} is in My Skills, waiting for you to accept it.`;
  return `${installed.name} v${installed.version} is in My Skills.`;
}

function sinceLine(at: string, now: number): string {
  const then = Date.parse(at);
  if (Number.isNaN(then)) return 'at some point';
  const gone = Math.max(0, now - then);
  if (gone < MINUTE_MS) return 'just now';
  if (gone < HOUR_MS) return counted(Math.floor(gone / MINUTE_MS), 'minute');
  if (gone < DAY_MS) return counted(Math.floor(gone / HOUR_MS), 'hour');
  return counted(Math.floor(gone / DAY_MS), 'day');
}

function counted(count: number, unit: string): string {
  return count === 1 ? `1 ${unit} ago` : `${count} ${unit}s ago`;
}

function listed(items: readonly string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items.at(-1) ?? ''}`;
}
