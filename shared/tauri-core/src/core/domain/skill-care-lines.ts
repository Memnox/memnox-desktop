import type { SkillCalibration, SkillStatsView } from '@memnox/core/wire';

/** The Skills page's words for a skill's use, its fix backlog and a suggested fix, ported from the Mac's `SkillCareLines`. */

/** Uses, failures and refusals in one line, or that the chats lately never used it. */
export function careCounts(stats: SkillStatsView | undefined): string {
  if (stats === undefined || (stats.uses === 0 && stats.failures === 0 && stats.refusals === 0)) return 'Not used in the last 30 days';
  const uses = stats.uses === 1 ? 'Used once' : `Used ${stats.uses} times`;
  const failures = stats.failures === 1 ? '1 failure' : `${stats.failures} failures`;
  const refusals = stats.refusals === 1 ? '1 refusal' : `${stats.refusals} refusals`;
  return `${uses}, ${failures}, ${refusals} in the last 30 days`;
}

/** What Calibrate builds the suggestion from, so the button says it before it is pressed. */
export function calibrateHint(stats: SkillStatsView | undefined): string | undefined {
  if (stats === undefined) return undefined;
  const notes = stats.notes.length;
  const failures = stats.recentFailures.length;
  if (notes === 0 && failures === 0) return NOTHING_TO_FIX;
  const noted = notes === 1 ? '1 note' : `${notes} notes`;
  const failed = failures === 1 ? '1 failure' : `${failures} failures`;
  return `Builds a Known issues section from ${noted} and ${failed}.`;
}

export const NOTHING_TO_FIX = 'Nothing noted and nothing failed, so there is no fix to suggest.';

/** The suggestion's header: the version it moves to. */
export function suggestionTitle(calibration: Pick<SkillCalibration, 'draft'>, current: string): string {
  return `Suggested fix: ${current} to ${calibration.draft.version}`;
}

/** A note as the runtime keeps it, one line, or undefined when nothing was typed. */
export function noteLine(typed: string): string | undefined {
  const line = typed.split(/\r\n|\r|\n/).join(' ').trim();
  return line === '' ? undefined : line;
}

export type DiffMark = 'same' | 'added' | 'removed';

export interface PlanDiffLine {
  readonly mark: DiffMark;
  readonly text: string;
  readonly index: number;
}

/** Two versions of some lines as one list marked kept, added or removed, on their longest common run, as the Mac's diff. */
export function lineDiff(before: readonly string[], after: readonly string[]): PlanDiffLine[] {
  const common = longestCommon(before, after);
  const lines: [DiffMark, string][] = [];
  let b = 0;
  let a = 0;
  for (const line of common) {
    while (b < before.length && before[b] !== line) lines.push(['removed', before[b++] ?? '']);
    while (a < after.length && after[a] !== line) lines.push(['added', after[a++] ?? '']);
    lines.push(['same', line]);
    b += 1;
    a += 1;
  }
  for (; b < before.length; b += 1) lines.push(['removed', before[b] ?? '']);
  for (; a < after.length; a += 1) lines.push(['added', after[a] ?? '']);
  return lines.map(([mark, text], index) => ({ mark, text, index }));
}

function longestCommon(x: readonly string[], y: readonly string[]): string[] {
  if (x.length === 0 || y.length === 0) return [];
  const table = Array.from({ length: x.length + 1 }, () => new Array<number>(y.length + 1).fill(0));
  const at = (i: number, j: number) => table[i]?.[j] ?? 0;
  for (let i = x.length - 1; i >= 0; i -= 1) {
    for (let j = y.length - 1; j >= 0; j -= 1) {
      const row = table[i];
      if (row !== undefined) row[j] = x[i] === y[j] ? at(i + 1, j + 1) + 1 : Math.max(at(i + 1, j), at(i, j + 1));
    }
  }
  const common: string[] = [];
  let i = 0;
  let j = 0;
  while (i < x.length && j < y.length) {
    if (x[i] === y[j]) {
      common.push(x[i] ?? '');
      i += 1;
      j += 1;
    } else if (at(i + 1, j) >= at(i, j + 1)) i += 1;
    else j += 1;
  }
  return common;
}
