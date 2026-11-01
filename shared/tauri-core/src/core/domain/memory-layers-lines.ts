import type { DaemonResponse } from '@memnox/core/wire';

/**
 * The Layers view's words, ported from the Mac's `MemoryLayersLines`: every one built here from what the runtime
 * answered, so the page only draws, and a number shows only where the runtime measured it.
 */

export type MemoryLayersView = NonNullable<DaemonResponse['memoryLayers']>;
export type ProjectLayersView = MemoryLayersView['projects'][number];
export type MemoryValueView = MemoryLayersView['value'];
export type MemoryLayersPlan = NonNullable<DaemonResponse['memoryLayersPlan']>;
export type SessionCostView = NonNullable<DaemonResponse['sessionCost']>;

/** One of the three layer cards, numbered as the long term memory stack reads. */
export interface LayerCard {
  readonly number: number;
  /** The file: MEMORY.md, the router's own name, or SKILL.md. */
  readonly file: string;
  /** What the layer is for, in two or three words. */
  readonly role: string;
  readonly state: string;
  /** The layer is there and does its job, so the card draws as settled. */
  readonly settled: boolean;
}

/** One line of the value strip, drawn only where the runtime measured the number in it. */
export interface ValueLine {
  readonly title: string;
  readonly figure: string;
  readonly detail: string;
}

export type PlanDiffMark = 'added' | 'removed' | 'same';

export interface PlanDiffLine {
  readonly mark: PlanDiffMark;
  readonly text: string;
  /** Its place in the diff, so two equal lines stay two rows. */
  readonly index: number;
}

/** The router file a project's first agent reads, or CLAUDE.md where it has none yet. */
export const DEFAULT_ROUTER = 'CLAUDE.md';

export const LAYERS_EMPTY = { title: 'No project yet', detail: 'Open a repository in an agent and its memory layers show here.' } as const;
export const COST_FOOTNOTE = 'Counted from your chats only. Nothing is pinged to keep them warm.';
export const KEEP_TITLE = 'Keep when a chat compacts, one line each';
export const PLAN_CONFIRM = {
  title: 'Write the memory map?',
  detail: 'Your own words in these files stay as they are.',
  confirm: 'Write',
} as const;

/** Thousands set apart by commas whatever the locale, so a count reads the same everywhere. */
export function grouped(n: number): string {
  const digits = String(Math.abs(Math.trunc(n)));
  const parts: string[] = [];
  for (let end = digits.length; end > 0; end -= 3) parts.unshift(digits.slice(Math.max(0, end - 3), end));
  return `${n < 0 ? '-' : ''}${parts.join(',')}`;
}

function plural(noun: string): string {
  return noun.endsWith('ch') ? `${noun}es` : `${noun}s`;
}

function count(n: number, noun: string): string {
  return n === 1 ? `1 ${noun}` : `${grouped(n)} ${plural(noun)}`;
}

function dollars(usd: number): string {
  return `$${usd.toFixed(2)}`;
}

function indexCard(index: ProjectLayersView['index']): LayerCard {
  if (!index.present) return { number: 1, file: index.path, role: 'every chat', state: 'Not written yet', settled: false };
  const lines = count(index.lines, 'line');
  const state = index.unlinked === 0 ? `${lines}, each linked to its file` : `${lines}, ${count(index.unlinked, 'line')} linked to no file`;
  return { number: 1, file: index.path, role: 'every chat', state, settled: index.unlinked === 0 };
}

function routerCard(routers: ProjectLayersView['routers']): LayerCard {
  const router = routers.find((each) => each.present) ?? routers[0];
  if (router === undefined) return { number: 2, file: DEFAULT_ROUTER, role: 'the router', state: 'No agent reads one here yet', settled: false };
  if (!router.present) return { number: 2, file: router.path, role: 'the router', state: 'Not written yet', settled: false };
  const total = router.departments.length;
  const state = total === 0 ? `${count(router.lines, 'line')}, no departments to route` : `Routes ${router.routed} of ${count(total, 'department')}`;
  return { number: 2, file: router.path, role: 'the router', state, settled: router.routed === total };
}

function skillsCard(skills: ProjectLayersView['skills']): LayerCard {
  if (skills.length === 0) return { number: 3, file: 'SKILL.md', role: 'live data', state: 'No SKILL.md in this project', settled: false };
  const live = skills.filter((skill) => skill.liveData).length;
  return { number: 3, file: 'SKILL.md', role: 'live data', state: `${count(skills.length, 'skill')}, ${live} say where live data is`, settled: live > 0 };
}

export function layerCards(project: ProjectLayersView): LayerCard[] {
  return [indexCard(project.index), routerCard(project.routers), skillsCard(project.skills)];
}

/** Faster to find and cheaper to find, each only where its number was measured, so nothing is invented. */
export function valueLines(value: MemoryValueView | undefined): ValueLine[] {
  if (value === undefined) return [];
  const lines: ValueLine[] = [];
  if (value.searchMedianMs !== undefined && value.searches !== undefined && value.searches > 0) {
    lines.push({ title: 'Faster to find', figure: `${Math.round(value.searchMedianMs)} ms`, detail: `median over the last ${count(value.searches, 'search')}` });
  }
  if (value.contextTokensSaved !== undefined && value.contextTokensSaved > 0) {
    lines.push({ title: 'Cheaper to find', figure: `${grouped(value.contextTokensSaved)} tokens`, detail: 'not read because memnox_context answered' });
  }
  return lines;
}

/** The short term memory card: the count first, then money only where every model was priced. */
export function sessionCostLines(cost: SessionCostView): string[] {
  const lines = [`${count(cost.coldReloads, 'cold reload')} in ${cost.days} days, over ${count(cost.sessions, 'chat')}`];
  if (cost.coldReloads > 0) lines.push(`${grouped(cost.reloadedTokens)} tokens written into the cache again`);
  if (cost.reloadCostUsd !== undefined) lines.push(`Reloading cost ${dollars(cost.reloadCostUsd)} at API prices`);
  if (cost.warmSavingUsd !== undefined) {
    const hours = Math.round(cost.warmHours);
    lines.push(cost.warmSavingUsd > 0 ? `Keeping chats warm ${hours}h would have saved ${dollars(cost.warmSavingUsd)}` : `Keeping chats warm ${hours}h would have cost more than it saved`);
  }
  if (cost.unpricedModels.length > 0) lines.push(`No price is known for ${cost.unpricedModels.join(', ')}, so no total is given`);
  return lines;
}

/** What confirming would write, in a line. */
export function planSummary(plan: MemoryLayersPlan): string {
  const changed = plan.files.filter((file) => file.changed).length;
  const same = plan.files.length - changed;
  if (changed === 0) return 'Everything is already as the map would write it.';
  const tail = same === 0 ? '' : `, ${same} already as planned`;
  return `Writes ${count(changed, 'file')}${tail}. Only what sits inside Memnox's fenced blocks changes.`;
}

function longestCommon(x: readonly string[], y: readonly string[]): string[] {
  if (x.length === 0 || y.length === 0) return [];
  const table = Array.from({ length: x.length + 1 }, () => new Array<number>(y.length + 1).fill(0));
  const at = (i: number, j: number) => table[i]?.[j] ?? 0;
  for (let i = x.length - 1; i >= 0; i -= 1) {
    for (let j = y.length - 1; j >= 0; j -= 1) {
      (table[i] as number[])[j] = x[i] === y[j] ? at(i + 1, j + 1) + 1 : Math.max(at(i + 1, j), at(i, j + 1));
    }
  }
  const common: string[] = [];
  let i = 0;
  let j = 0;
  while (i < x.length && j < y.length) {
    if (x[i] === y[j]) {
      common.push(x[i] as string);
      i += 1;
      j += 1;
    } else if (at(i + 1, j) >= at(i, j + 1)) i += 1;
    else j += 1;
  }
  return common;
}

/** A line diff from before to after, kept in order, so the sheet shows exactly what moves. */
export function planDiff(before: readonly string[], after: readonly string[]): PlanDiffLine[] {
  const lines: [PlanDiffMark, string][] = [];
  let b = 0;
  let a = 0;
  for (const line of longestCommon(before, after)) {
    while (b < before.length && before[b] !== line) lines.push(['removed', before[b++] as string]);
    while (a < after.length && after[a] !== line) lines.push(['added', after[a++] as string]);
    lines.push(['same', line]);
    b += 1;
    a += 1;
  }
  for (; b < before.length; b += 1) lines.push(['removed', before[b] as string]);
  for (; a < after.length; a += 1) lines.push(['added', after[a] as string]);
  return lines.map(([mark, text], index) => ({ mark, text, index }));
}

/** A keep list typed one line each, blank lines dropped. */
export function keepList(typed: string): string[] {
  return typed
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '');
}

/** What a written plan comes to, said above the view. */
export function writtenLine(files: readonly string[]): string {
  return files.length === 0 ? 'Nothing needed writing.' : `Wrote ${files.join(', ')}.`;
}

/** What the brain says it is standing on, so a saved or partial workspace picture never reads as whole and live. */
export function workspaceGraphLine(graph: { source: string; fallback?: string; withheld: number; truncated: boolean }): string | undefined {
  const parts: string[] = [];
  if (graph.source === 'saved') {
    if (graph.fallback === 'not-joined') parts.push('This computer is not in a workspace, so only what it keeps itself is drawn');
    else if (graph.fallback === 'unreachable') parts.push('Memnox Cloud did not answer in time, so the workspace is drawn from what this computer last saved');
    else if (graph.fallback === 'refused') parts.push('Memnox Cloud refused the read, so the workspace is drawn from what this computer last saved');
    else parts.push('The workspace is drawn from what this computer last saved');
  }
  if (graph.withheld > 0) parts.push(`${grouped(graph.withheld)} kept back by this computer's clearance`);
  if (graph.truncated) parts.push('cut at the most the cloud draws at once');
  return parts.length === 0 ? undefined : `${parts.join(', ')}.`;
}
