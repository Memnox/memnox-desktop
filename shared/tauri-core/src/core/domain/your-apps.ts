import type { DaemonResponse, ToolConnection } from '@memnox/core/wire';
import { toolkitName } from './tool-brand';

/**
 * The Connectors page, ported from the Mac's `YourApps`, `YourAppNote`, `YourAppPress`, `YourAppDisconnect`,
 * `FeaturedToolkits` and `ConnectorOrderLines`: Connected, Recommended and All as tabs over a categories rail, one
 * search and one grid of cards, each card the console's connector card. The words are the Mac's, with "this computer"
 * where the Mac says "this Mac", so a test pins them alike on every desktop.
 */

/** One tool the catalogue offers, by the slug connections-sign-in takes. */
export type CatalogueTool = NonNullable<DaemonResponse['toolkits']>[number];

/** Where one tool stands for the person at this computer, which decides the words on its card and its one button. */
export type YourAppStanding = 'on-this-computer' | 'connected' | 'sign-in-again' | 'available';

/** The three views of the person's tools, as the console's connectors page has them. */
export type YourAppsTab = 'connected' | 'recommended' | 'all';
export const YOUR_APPS_TABS: readonly YourAppsTab[] = ['connected', 'recommended', 'all'];

/** The one line under a tool's name, by where it stands. */
export const STANDING_LINE: Record<YourAppStanding, string> = {
  'on-this-computer': 'Already on this computer',
  connected: 'Connected',
  'sign-in-again': 'Sign in again to use it',
  available: 'Sign in with your own account',
};

/** One card, drawn as the console's connector card: a tool, the catalogue's words and tags for it, and where it stands. */
export interface YourAppCard {
  readonly slug: string;
  readonly name: string;
  readonly logo: string | undefined;
  readonly standing: YourAppStanding;
  readonly description: string | undefined;
  readonly categories: readonly string[];
  readonly kind: CatalogueTool['kind'];
  readonly support: CatalogueTool['support'];
  /** When its working sign in was made, for "Connected since". */
  readonly connectedSince: Date | undefined;
  /** The agents that worked in it through Memnox lately, newest first. */
  readonly uses: readonly NonNullable<ToolConnection['usedBy']>[number][];
  readonly source: CatalogueTool['source'];
  readonly weight: number | undefined;
}

/** One row of the categories rail: the folded tag a card is matched on, the spelling a person reads, and how many. */
export interface YourAppCategory {
  readonly id: string;
  readonly label: string;
  readonly count: number;
}

/** The tools offered before anybody has searched, the same ones the cloud puts first, carried so they show signed out. */
export const FEATURED_TOOLKITS = ['gmail', 'googlecalendar', 'googledocs', 'googledrive', 'outlook', 'notion', 'slack', 'github', 'linear', 'jira'];

/** The layout numbers of the Mac's page, so both desktops lay the grid and the rail out alike. */
export const YourAppsLayout = {
  /** Wide enough that a name, its pill and a full width Connect never crowd, three across in the page's column. */
  cardMinimum: 240,
  gridSpacing: 16,
  railWidth: 200,
  railSpacing: 24,
  /** The console shows about twenty before the rest are folded away. */
  railLeading: 20,
  markSide: 40,
  cardPadding: 20,
} as const;

/** Every word on the page that is not built from a tool, as the Mac's page writes it. */
export const YourAppsLines = {
  checkAgain: 'Check again',
  searchAll: 'Search every app you can connect',
  searchThese: 'Search these apps',
  categories: 'Categories',
  allToolkits: 'All toolkits',
  reading: 'Reading your apps',
  readingDetail: 'This takes a moment.',
  noApps: 'No apps yet',
  noAppsDetail: 'Connect one from Recommended or All and sign in to it in your browser.',
  tryAnother: 'Try another name for the app.',
  searchAllDetail: 'Search All to look through every app you can connect.',
  signInTitle: 'Sign in to Memnox Cloud to connect',
  signInDetail: 'Connecting your apps needs a Memnox Cloud account. It is what connects them and what works in them as you.',
  signInButton: 'Sign in to connect',
  signIn: 'Sign in',
  allowance: 'Free includes 500 actions a month in your apps once you sign in to Memnox Cloud. Paid plans have no limit.',
  recommended: 'Recommended',
  waiting: 'Finish signing in in your browser',
  onThisComputerFoot: 'Your agents reach it here, so there is nothing to connect.',
  connect: 'Connect',
  disconnect: 'Disconnect',
  signInAgain: 'Sign in again',
  anotherAccount: 'Use another account',
  reachedHere: 'Reached from this computer itself',
  ownAccount: 'Your own account',
  throughMemnox: 'Your agents can use it through Memnox',
  close: 'Close',
} as const;

export const SIGN_IN_STOPPED = 'Signing in to Memnox Cloud did not finish, so nothing was connected.';

/** A tab's title, Connected with how many the person has. */
export function tabTitle(tab: YourAppsTab, connectedCount: number): string {
  if (tab === 'connected') return `Connected (${connectedCount})`;
  return tab === 'recommended' ? 'Recommended' : 'All';
}

/** The tab on screen: the one picked, else All for a search, Connected for somebody with apps and Recommended otherwise. */
export function tabOf(chosen: YourAppsTab | undefined, query: string, yours: number): YourAppsTab {
  if (chosen !== undefined) return chosen;
  if (query.trim() !== '') return 'all';
  return yours === 0 ? 'recommended' : 'connected';
}

/** The connection's `local`, which an older wire leaves out. */
type YourConnection = ToolConnection & { readonly local?: true };

export function standingOf(connection: YourConnection): YourAppStanding {
  if (connection.local === true) return 'on-this-computer';
  return connection.connected ? 'connected' : 'sign-in-again';
}

function trimmed(text: string | undefined): string | undefined {
  const words = text?.trim();
  return words === undefined || words === '' ? undefined : words;
}

/** An instant as the cloud writes it; undefined for anything that is no date. */
function dateOf(text: string | undefined): Date | undefined {
  if (text === undefined || text === '') return undefined;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function card(slug: string, name: string, standing: YourAppStanding, connection: YourConnection | undefined, tool: CatalogueTool | undefined): YourAppCard {
  return {
    slug,
    name,
    logo: tool?.logo,
    standing,
    description: trimmed(tool?.description),
    categories: tool?.categories ?? [],
    kind: tool?.kind,
    support: tool?.support,
    connectedSince: dateOf(connection?.connectedAt),
    uses: connection?.usedBy ?? [],
    source: tool?.source,
    weight: tool?.weight,
  };
}

function rank(card: YourAppCard): number {
  if (card.standing === 'on-this-computer') return 0;
  return card.standing === 'available' ? 2 : 1;
}

function bySlug(found: readonly CatalogueTool[]): Map<string, CatalogueTool> {
  const named = new Map<string, CatalogueTool>();
  for (const tool of found) if (!named.has(tool.slug)) named.set(tool.slug, tool);
  return named;
}

/** What the person has, those on this computer first and then by name, each described by the catalogue where it answered. */
export function yours(connections: readonly YourConnection[], found: readonly CatalogueTool[] = []): YourAppCard[] {
  const named = bySlug(found);
  const seen = new Set<string>();
  return connections
    .filter((connection) => !seen.has(connection.toolkit) && seen.add(connection.toolkit) !== undefined)
    .map((connection) => {
      const tool = named.get(connection.toolkit);
      return card(connection.toolkit, tool?.name ?? toolkitName(connection.toolkit), standingOf(connection), connection, tool);
    })
    .sort((a, b) => (rank(a) !== rank(b) ? rank(a) - rank(b) : a.name.localeCompare(b.name, 'en', { sensitivity: 'base' })));
}

/** The catalogue's tools, each marked with where it stands, so a tool already connected says so. */
export function catalogue(found: readonly CatalogueTool[], connections: readonly YourConnection[]): YourAppCard[] {
  const have = new Map<string, YourConnection>();
  for (const connection of connections) if (!have.has(connection.toolkit)) have.set(connection.toolkit, connection);
  const seen = new Set<string>();
  return found
    .filter((tool) => !seen.has(tool.slug) && seen.add(tool.slug) !== undefined)
    .map((tool) => {
      const connection = have.get(tool.slug);
      return card(tool.slug, tool.name, connection === undefined ? 'available' : standingOf(connection), connection, tool);
    });
}

/** The featured tools, connected or not, named and drawn as the catalogue has them where it has answered. */
export function recommended(found: readonly CatalogueTool[], connections: readonly YourConnection[]): YourAppCard[] {
  const named = bySlug(found);
  return catalogue(
    FEATURED_TOOLKITS.map((slug) => named.get(slug) ?? { slug, name: toolkitName(slug) }),
    connections,
  );
}

/** The catalogue as the page offers it: what the search found, or the featured tools where it could not be read. */
export function offered(found: readonly CatalogueTool[], searchFailed: boolean, query: string, connections: readonly YourConnection[]): YourAppCard[] {
  if (!searchFailed || query.trim() !== '') return catalogue(found, connections);
  return catalogue(
    FEATURED_TOOLKITS.map((slug) => ({ slug, name: toolkitName(slug) })),
    connections,
  );
}

/** Cards narrowed to what was typed, by name or slug, as the Connected and Recommended tabs search. */
export function narrowed(cards: readonly YourAppCard[], query: string): YourAppCard[] {
  const typed = query.trim().toLowerCase();
  if (typed === '') return [...cards];
  return cards.filter((each) => each.name.toLowerCase().includes(typed) || each.slug.toLowerCase().includes(typed));
}

/** The provider spells one category several ways, "Team Chat" and "team-chat", so both fold to one before counting. */
export function fold(category: string): string {
  return category
    .toLowerCase()
    .replace(/&/g, 'and')
    .split(/[^a-z0-9]+/)
    .filter((part) => part !== '')
    .join('-');
}

const hasCapital = (text: string) => /\p{Lu}/u.test(text);

/** Words read rather than typed, so these stay in capitals. */
const ACRONYMS = new Set(['ai', 'api', 'cms', 'crm', 'erp', 'hr', 'it', 'lms', 'seo', 'sms']);

/** A tag that arrived lowercase is cased as the console cases it; one already capitalised is left alone. */
function asWritten(label: string): string {
  if (hasCapital(label)) return label;
  return label
    .split(' ')
    .filter((word) => word !== '')
    .map((word) => (ACRONYMS.has(word) ? word.toUpperCase() : word.charAt(0).toUpperCase() + word.slice(1)))
    .join(' ');
}

/** Every category on these cards, commonest first, each card counted once however it spells a tag. */
export function categoriesOf(cards: readonly YourAppCard[]): YourAppCategory[] {
  const found = new Map<string, { label: string; count: number }>();
  for (const each of cards) {
    const counted = new Set<string>();
    for (const raw of each.categories) {
      const id = fold(raw);
      if (id === '' || counted.has(id)) continue;
      counted.add(id);
      const held = found.get(id);
      // A spelling with capitals is the written one, CRM over crm.
      const label = held === undefined ? raw : hasCapital(held.label) || !hasCapital(raw) ? held.label : raw;
      found.set(id, { label, count: (held?.count ?? 0) + 1 });
    }
  }
  return [...found.entries()]
    .map(([id, held]) => ({ id, label: asWritten(held.label), count: held.count }))
    .sort((a, b) => (a.count !== b.count ? b.count - a.count : a.label.localeCompare(b.label, 'en')));
}

/** Whether a card carries the category, by its folded tag; undefined is every card. */
export function inCategory(each: YourAppCard, category: string | undefined): boolean {
  return category === undefined || each.categories.some((raw) => fold(raw) === category);
}

/** The count beside the search: those shown of those in the tab before a category narrows it. */
export function showingLine(showing: number, total: number): string {
  return `${showing} of ${total}`;
}

/** The empty state's title when nothing matches, counted rather than estimated. */
export function countLine(count: number, query: string): string {
  const typed = query.trim();
  const apps = count === 1 ? '1 app' : `${count} apps`;
  if (typed === '') return count === 0 ? 'No apps to show' : apps;
  return count === 0 ? `No app matches “${typed}”` : `${apps} ${count === 1 ? 'matches' : 'match'} “${typed}”`;
}

/** A date as the console's card writes it: Oct 2, 2026. */
export function since(date: Date): string {
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).format(date);
}

/** The line under the name: the cloud's kind for it where it said one, else how the tool is reached. */
export function reachLine(each: YourAppCard): string {
  if (each.standing === 'on-this-computer') return YourAppsLines.reachedHere;
  switch (each.kind) {
    case 'record':
      return 'System of record';
    case 'conversation':
      return 'System of conversation';
    case 'other':
      return 'Other';
    default:
      return YourAppsLines.ownAccount;
  }
}

/** The pill beside the name, in the console's words; undefined where the cloud did not say how fully it reads it. */
export function supportPill(each: YourAppCard): string | undefined {
  if (each.support === 'full') return 'Fully supported';
  return each.support === 'partial' ? 'Limited support' : undefined;
}

/** Where a connector comes from, as its chip says it. */
export function sourceChip(source: NonNullable<CatalogueTool['source']>): string {
  switch (source) {
    case 'official':
      return 'Official';
    case 'cli':
      return 'CLI';
    case 'api':
      return 'API';
    case 'mcp':
      return 'Community MCP';
  }
}

/** The legend above the list, so the order is said once rather than guessed from the chips. */
export const ORDER_LEGEND = 'Searched in order: Official, then CLI, then API, then community MCP';

/** The order chip, such as Official 4, or undefined where the runtime did not say where it comes from. */
export function orderChip(each: YourAppCard): string | undefined {
  if (each.source === undefined) return undefined;
  return each.weight === undefined ? sourceChip(each.source) : `${sourceChip(each.source)} ${each.weight}`;
}

/** The status line, as the console's card says it; a sign in open in the browser says to finish it there. */
export function statusLine(each: YourAppCard, waiting: boolean): string {
  if (waiting) return YourAppsLines.waiting;
  switch (each.standing) {
    case 'on-this-computer':
      return 'On this computer';
    case 'connected':
      return each.connectedSince === undefined ? 'Connected' : `Connected since ${since(each.connectedSince)}`;
    case 'sign-in-again':
      return STANDING_LINE['sign-in-again'];
    case 'available':
      return 'Not connected';
  }
}

/** The tone of the status dot and words. */
export function statusTone(each: YourAppCard, waiting: boolean): 'good' | 'attention' | 'quiet' {
  if (waiting || each.standing === 'sign-in-again') return 'attention';
  return each.standing === 'available' ? 'quiet' : 'good';
}

/** Names joined as a sentence says them: "A", "A and B", "A, B and C". */
function listed(names: readonly string[]): string {
  const last = names.at(-1);
  if (last === undefined) return '';
  return names.length === 1 ? last : `${names.slice(0, -1).join(', ')} and ${last}`;
}

/** The line under the status on a connected app: that agents reach it, and which did lately where any did. */
export function agentsLine(each: YourAppCard, name: (agent: string) => string): string | undefined {
  if (each.standing !== 'connected') return undefined;
  const named = each.uses.map((use) => name(use.agent));
  if (named.length === 0) return YourAppsLines.throughMemnox;
  return `${YourAppsLines.throughMemnox}. Used lately by ${listed(named)}`;
}

/** What a press was for, so a note that it did not work can say which. */
export type YourAppAct = 'connect' | 'disconnect' | 'cloud-sign-in';

/** Something that did not work, held on the card it came from, or over the grid for one about the page. */
export interface YourAppNote {
  readonly toolkit: string | undefined;
  readonly title: string;
  readonly words: string;
}

/** The daemon's words as one clean sentence: no stray space or line break, and a full stop where it left one off. */
export function sentence(said: string | undefined): string | undefined {
  if (said === undefined) return undefined;
  const words = said.split(/\s+/).filter((word) => word !== '').join(' ');
  if (words === '') return undefined;
  return /[.!?]$/.test(words) ? words : `${words}.`;
}

/** The note for a press that did not work, in the daemon's own words where it gave any and a plain line where not. */
export function failedNote(act: YourAppAct, toolkit: string | undefined, said: string | undefined): YourAppNote {
  const name = toolkit === undefined ? 'the app' : toolkitName(toolkit);
  const [title, fallback] =
    act === 'connect'
      ? [`Could not connect ${name}`, 'Nothing was connected. Try again in a moment.']
      : act === 'disconnect'
        ? [`Could not disconnect ${name}`, 'It is still connected. Try again in a moment.']
        : ['Not signed in to Memnox Cloud', SIGN_IN_STOPPED];
  return { toolkit, title, words: sentence(said) ?? fallback };
}

/** True where the list shows the app working or reached on this computer itself, so there is nothing left to connect. */
export function isSettled(toolkit: string, connections: readonly YourConnection[]): boolean {
  const slug = toolkit.toLowerCase();
  return connections.some((each) => each.toolkit.toLowerCase() === slug && (each.connected || each.local === true));
}

/** True where the press opens a sign in: always to use another account, else only for an app not working yet. */
export function opensSignIn(toolkit: string, again: boolean, connections: readonly YourConnection[]): boolean {
  return again || !isSettled(toolkit, connections);
}

/** What the disconnect dialog says: the cloud stops reading the app, agents stop working in it, and what was learned stays. */
export const YourAppDisconnect = {
  title: (name: string) => `Disconnect ${name}?`,
  message: (name: string) => `Memnox stops reading from ${name} straight away.`,
  detail: (name: string) => `Your agents stop working in ${name} as you until you connect it again. What Memnox already learned from it stays on this computer.`,
  confirm: 'Disconnect',
  cancel: 'Cancel',
} as const;
