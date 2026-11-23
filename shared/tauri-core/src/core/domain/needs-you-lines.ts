import type { ActivityRow } from '@memnox/core/wire';
import { activityWords } from './activity-words';
import { answeredWords } from './studio-lines';

/**
 * The three views of Needs you, the Mac's `NeedsYouView`: what waits on the person now, what nobody answered in time and
 * was kept while its agent carries on, and what they already decided today, so a person who answered on the island or
 * the phone sees what they said yes and no to without opening Activity.
 */
export type NeedsYouView = 'waiting' | 'kept' | 'decided';

export const NEEDS_YOU_VIEWS: readonly NeedsYouView[] = ['waiting', 'kept', 'decided'];

export const NeedsYouLines = {
  view: { waiting: 'Waiting for you', kept: 'Kept for later', decided: 'Decided today' } satisfies Record<NeedsYouView, string>,
  noneKept: 'Nothing is kept for later.',
  noneKeptDetail: 'A question nobody answered in time waits here while its agent carries on with other work.',
  noneDecided: 'Nothing was decided today.',
  noneDecidedDetail: 'What you allow or stop on the island or your phone shows here for the rest of the day.',
} as const;

export interface DecidedLine {
  readonly id: string;
  readonly title: string;
  readonly caption: string;
  readonly outcome: string;
  readonly allowed: boolean;
}

/** Today's rows a person answered, newest first as the record reads them. */
export function decidedLines(rows: readonly ActivityRow[]): DecidedLine[] {
  return rows.flatMap((row) => {
    const answered = answeredWords(row);
    if (answered === undefined) return [];
    const target = row.target === undefined ? {} : { target: row.target };
    return [
      {
        id: row.id,
        title: activityWords({ operation: row.operation, ...target }),
        caption: [row.agentName, answered].join(' · '),
        outcome: row.effect === 'allow' ? 'Let go ahead' : row.effect === 'deny' ? 'Stopped' : 'Answered',
        allowed: row.effect === 'allow',
      },
    ];
  });
}
