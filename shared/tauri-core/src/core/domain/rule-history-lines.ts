import type { RuleHistoryRow } from '@memnox/core/wire';
import { ago } from './session-text';

/** One rule change as Rules' History lists it. Mirrors the Mac's `RuleHistoryLine`. */
export interface RuleHistoryLine {
  readonly id: string;
  readonly title: string;
  readonly caption: string;
  readonly outcome: string;
  readonly inForce: boolean;
}

/** The words for Rules' History: what changed, who said so and when, and whether it holds. */
export const RuleHistoryLines = {
  title: 'History',
  empty: 'No rule has changed on this computer yet. A rule you add or take out shows here once you answer it.',
} as const;

export function ruleHistoryLines(rows: readonly RuleHistoryRow[], now: number): RuleHistoryLine[] {
  return rows.map((row) => {
    const removed = row.kind === 'removed';
    const confirmed = row.answer === 'confirmed';
    const what = row.rules.join(' ');
    const verb = confirmed ? 'Signed' : 'Declined';
    const who = row.answeredBy === undefined ? verb : `${verb} by ${row.answeredBy}`;
    const when = ago(row.answeredAt, now);
    return {
      id: row.id,
      title: removed ? `Take out ${what}` : what,
      caption: when === undefined ? who : `${who}, ${when}`,
      outcome: confirmed ? (removed ? 'Taken out' : 'In force') : 'Left as it was',
      inForce: confirmed && !removed,
    };
  });
}
