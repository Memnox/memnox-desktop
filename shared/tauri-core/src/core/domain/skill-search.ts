import type { FoundSkillView, SkillView } from '@memnox/core/wire';

/**
 * The Skills page's search and the Found on this computer list's words, ported from the Mac's `SkillSearch`. One
 * query narrows both the hub and what agents already had, matched on what a person can see in each row and never on a score.
 */

/** Rows a group shows before its Show all, so one agent with many skills does not bury the rest. */
export const COLLAPSED_ROWS = 5;

export interface FoundSkillGroup {
  readonly agent: string;
  readonly label: string;
  readonly skills: readonly FoundSkillView[];
}

/** What an Import all came to, counted so one line says it. */
export interface ImportResults {
  readonly done: number;
  readonly proposed: number;
  readonly failed: readonly string[];
}

function fold(text: string): string {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

/** The query as matched: case and accents set aside, undefined when nothing was typed. */
export function queryWords(query: string): string[] | undefined {
  const words = query.split(/\s+/).filter((word) => word !== '').map(fold);
  return words.length === 0 ? undefined : words;
}

/** Every word typed appears somewhere in the fields, so "higgs video" finds higgsfield-video-explainer. */
export function matchesQuery(fields: readonly string[], query: string): boolean {
  const words = queryWords(query);
  if (words === undefined) return true;
  const haystack = fold(fields.join(' '));
  return words.every((word) => haystack.includes(word));
}

/** The hub's skills a query keeps: by name, description, category and the agents each is given to. */
export function hubMatching<S extends Pick<SkillView, 'name' | 'description' | 'category' | 'agents'>>(skills: readonly S[], query: string, label: (agent: string) => string): S[] {
  return skills.filter((skill) => matchesQuery([skill.name, skill.description, skill.category ?? '', ...skill.agents.map(label), ...skill.agents], query));
}

/** What agents already had and is not in the hub yet, kept by a query on its name, agent, path and tools. */
export function foundMatching(found: readonly FoundSkillView[], query: string, label: (agent: string) => string): FoundSkillView[] {
  return found.filter((each) => !each.imported && matchesQuery([each.name, each.agent, label(each.agent), each.path, ...each.tools], query));
}

/** The found skills by agent, agents in the order of their labels and each agent's skills by name. */
export function groupedFound(found: readonly FoundSkillView[], label: (agent: string) => string): FoundSkillGroup[] {
  const byAgent = new Map<string, FoundSkillView[]>();
  for (const each of found) byAgent.set(each.agent, [...(byAgent.get(each.agent) ?? []), each]);
  return [...byAgent.entries()]
    .map(([agent, skills]) => ({ agent, label: label(agent), skills: [...skills].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) }))
    .sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true, sensitivity: 'base' }));
}

/** "12", or "3 of 12" while a search narrows the list. */
export function countedLine(shown: number, total: number, searching: boolean): string {
  return searching && shown !== total ? `${shown} of ${total}` : `${total}`;
}

export function noMatchTitle(query: string): string {
  return `No skills match “${query.trim()}”`;
}

/** What the empty search says next, pointing at the found list when it still holds matches. */
export function noMatchDetail(foundMatching: number): string {
  if (foundMatching === 0) return 'Nothing in the hub or on this computer has that in its name, description or agent.';
  const some = foundMatching === 1 ? '1 skill an agent already has matches' : `${foundMatching} skills agents already have match`;
  return `Nothing in the hub has that yet, but ${some} below, ready to import.`;
}

/** "Import all 83", or "Import 9 shown" while a search narrows the list, so the press says what it takes. */
export function importAllTitle(count: number, searching: boolean): string {
  return searching ? `Import ${count} shown` : `Import all ${count}`;
}

export function importingLine(done: number, total: number): string {
  return `Importing ${done} of ${total}`;
}

/** What an Import all came to, in one line. */
export function importedLine(results: ImportResults): string {
  const parts: string[] = [];
  if (results.done > 0) parts.push(results.done === 1 ? '1 skill is in the hub now.' : `${results.done} skills are in the hub now.`);
  if (results.proposed > 0) parts.push(results.proposed === 1 ? '1 waits for your signature on the island.' : `${results.proposed} wait for your signature on the island.`);
  const first = results.failed[0];
  if (first !== undefined) parts.push(results.failed.length === 1 ? `1 did not import: ${first}` : `${results.failed.length} did not import, and the first said: ${first}`);
  return parts.length === 0 ? 'Nothing was imported.' : parts.join(' ');
}

/** A path under the home folder written from ~, so the row reads the part that differs. */
export function shortPath(path: string, home: string | undefined): string {
  if (home === undefined) return path;
  const base = home.replace(/[\\/]$/, '');
  if (base === '' || !(path === base || path.startsWith(`${base}/`) || path.startsWith(`${base}\\`))) return path;
  return `~${path.slice(base.length)}`;
}

/** What a found skill reaches in a few words, or undefined where it declares nothing. */
export function foundReach(found: Pick<FoundSkillView, 'tools'>): string | undefined {
  if (found.tools.length === 0) return undefined;
  return `Uses ${listed(found.tools)}`;
}

function listed(items: readonly string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`;
}

/** The home folder a path sits under on macOS, Linux or Windows, read off the path itself since the webview knows no home. */
export function homeOf(path: string): string | undefined {
  return /^(\/Users\/[^/]+|\/home\/[^/]+|[A-Za-z]:\\Users\\[^\\]+)/.exec(path)?.[1];
}

/** Where its SKILL.md sits: the path itself when it names a markdown file, otherwise SKILL.md inside the folder. */
export function instructionsFile(found: Pick<FoundSkillView, 'path'>): string {
  if (found.path.toLowerCase().endsWith('.md')) return found.path;
  const windows = /^[A-Za-z]:\\/.test(found.path);
  const slash = windows ? '\\' : '/';
  return `${found.path.endsWith(slash) ? found.path : found.path + slash}SKILL.md`;
}
