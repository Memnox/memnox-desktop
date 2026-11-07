import type { CommunityIndexView, IndexEntryView, IndexInstalled, IndexKind, IndexNeedsView } from '@memnox/core/wire';
import { agentLabel } from './mcp-hub-lines';

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;
/** An https address with a host and no spaces; the runtime checks it again before anything is proposed. */
const HTTPS_ADDRESS = /^https:\/\/[^\s/?#]+[^\s]*$/i;

/** One kind of need, as Discover groups them: what it is called, what it means, and the word to count it in. */
export interface NeedsGroup {
  readonly title: string;
  readonly caption: string;
  readonly items: readonly string[];
}

/** The needs a manifest declares, in the order a person weighs them: what it touches first, what it asks for last. */
const NEEDS: readonly { key: keyof IndexNeedsView; title: string; caption: string; one: string; many: string }[] = [
  { key: 'filesystem', title: 'Files', caption: 'Paths it reads or writes', one: 'path', many: 'paths' },
  { key: 'network', title: 'Network', caption: 'Hosts it reaches', one: 'host', many: 'hosts' },
  { key: 'commands', title: 'Commands', caption: 'Commands it runs', one: 'command', many: 'commands' },
  { key: 'mcpServers', title: 'MCP servers', caption: 'MCP servers it uses', one: 'MCP server', many: 'MCP servers' },
  { key: 'tools', title: 'Tools', caption: 'Tools it asks its agent for', one: 'tool', many: 'tools' },
];

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

/** The kinds of need a listing declares, each with what it names, leaving out the kinds it names nothing in. */
export function needsGroups(needs: IndexNeedsView | undefined): NeedsGroup[] {
  if (needs === undefined) return [];
  return NEEDS.filter((each) => needs[each.key].length > 0).map((each) => ({ title: each.title, caption: each.caption, items: needs[each.key] }));
}

/** What a listing needs in a line, counted by kind, or that it declares nothing, or that it carries no manifest at all. */
export function needsSummaryLine(needs: IndexNeedsView | undefined): string {
  if (needs === undefined) return 'Says nothing about what it needs, since the index carries no manifest for it';
  const counts = NEEDS.filter((each) => needs[each.key].length > 0).map((each) => {
    const count = needs[each.key].length;
    return `${count} ${count === 1 ? each.one : each.many}`;
  });
  if (counts.length === 0) return 'Needs no files, network, commands, MCP servers or tools';
  return `Needs ${listed(counts)}`;
}

/** How many things to know before installing, or undefined when nothing stands out. */
export function warningsCountLine(warnings: readonly string[]): string | undefined {
  if (warnings.length === 0) return undefined;
  return warnings.length === 1 ? '1 thing to know before installing' : `${warnings.length} things to know before installing`;
}

/** Where listings come from, and whether that is the Memnox marketplace or an index somebody named. */
export function indexSourceLine(view: Pick<CommunityIndexView, 'source' | 'marketplace'>): string {
  if (view.marketplace) return `Listings come from the Memnox marketplace, at ${view.source}.`;
  return `Listings come from ${view.source}, an index you named rather than the Memnox marketplace.`;
}

/** Only an https address is offered to the runtime, which refuses anything else as well. */
export function isIndexAddress(text: string): boolean {
  return HTTPS_ADDRESS.test(text.trim());
}

/** Said when the address typed is not one the runtime would read. */
export const INDEX_ADDRESS_WANTED = 'Give an https address to an index.json.';

/** Said once another index is proposed: it holds only once signed, so the page still shows the current source. */
export function indexSourceProposedLine(keyTitle: string): string {
  return `Waiting on the island: sign it with ${keyTitle} and listings come from there.`;
}

/** Said once the marketplace is the source again, which narrows and so holds at once. */
export const INDEX_SOURCE_RESET = 'Listings come from the Memnox marketplace again.';

/** Said when the address named is already where listings come from, so nothing was proposed. */
export const INDEX_SOURCE_SAME = 'Listings already come from there.';

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

/** The Discover page's own words. */
export const DiscoverLines = {
  kinds: [
    { id: 'all', title: 'Everything' },
    { id: 'skill', title: 'Skills' },
    { id: 'rule_pack', title: 'Rule packs' },
  ] as const satisfies readonly { id: IndexKindFilter; title: string }[],
  readWhat: 'the community index',
  search: 'Search skills and rule packs',
  refreshHelp: 'Read the index again now',
  refresh: 'Refresh',
  kind: 'Kind',
  everyCategory: 'Every category',
  emptyTitle: 'Nothing in the index matches',
  emptyBody: 'Try fewer words, another kind or every category, or read the index again with Refresh.',
  sourceTitle: 'Where listings come from',
  marketplace: 'Memnox marketplace',
  named: 'An index you named',
  addressPlaceholder: 'https://example.com/index.json',
  propose: 'Propose this index',
  proposeWaits: (keyTitle: string) => `Another index decides what can be installed here, so naming one waits on the island for your signature with ${keyTitle}.`,
  useMarketplace: 'Use the Memnox marketplace',
  unsafe: 'Marked unsafe',
  view: 'View listing',
  back: 'Discover',
  publisher: 'Publisher',
  category: 'Category',
  license: 'License',
  agents: 'Agents',
  here: 'Here',
  noneGiven: 'None given',
  needs: 'What it needs',
  versions: 'Versions',
  newest: 'The newest version not marked unsafe',
  latest: 'Latest',
  yankedCaption: 'Marked unsafe since it was published, so it is never installed',
  unsafeWord: 'Unsafe',
  installing: 'Installing',
  install: (version: string) => `Install ${version}`,
  nothingToInstall: 'Every version is marked unsafe, so there is nothing to install',
  digestNote: 'The runtime checks what it downloads against the digest below before it writes anything.',
  digest: 'Digest',
} as const;
