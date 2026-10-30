import type { ActivityFilter, ActivityRow, LiveActivityRow } from '@memnox/core/wire';

/**
 * The rows the runtime sends as the ledger gains them, held against the filter a person is looking through. A
 * live row carries names only, so a filter it cannot be told against is never guessed: the row is counted for a
 * refresh, which reads it whole.
 */

/** A row as the activity list draws it, paged in whole or arrived live with names only. */
export type ShownActivity = Pick<ActivityRow, 'id' | 'at' | 'agent' | 'operation' | 'effect'> &
  Partial<Pick<ActivityRow, 'target' | 'agentName' | 'rule' | 'answeredBy' | 'answeredHow' | 'failed'>>;

/** Shown at once, left out because the filter excludes it, or not knowable from names alone. */
export type LiveMatch = 'shown' | 'hidden' | 'unknown';

/** The most live rows a list keeps above its first page; older ones are counted for a refresh rather than grown without end. */
export const MOST_LIVE_ROWS_KEPT = 200;

/**
 * Whether a live row belongs under a filter. The kind needs the surface a live row does not carry, so it is unknown;
 * a search is told on the operation, the target and the agent, and a match on the rule's name alone waits for a refresh.
 */
export function liveMatch(row: LiveActivityRow, filter: ActivityFilter): LiveMatch {
  if (filter.effect !== undefined && row.effect !== filter.effect) return 'hidden';
  if (filter.agent !== undefined && row.agent !== filter.agent) return 'hidden';
  if (filter.since !== undefined && row.at < filter.since) return 'hidden';
  if (filter.until !== undefined && row.at > filter.until) return 'hidden';
  const text = filter.text?.trim().toLowerCase() ?? '';
  if (text !== '' && ![row.operation, row.target ?? '', row.agent].some((name) => name.toLowerCase().includes(text))) return 'hidden';
  if (filter.kind !== undefined) return 'unknown';
  return 'shown';
}

/** The pill over a list scrolled away from its top. */
export function newRowsLine(count: number): string {
  return `${count} new`;
}

/** Said under the live rows when some could not be carried or told against the filter. */
export function missedRowsLine(count: number): string {
  return `and ${count} more, refresh to see them`;
}

/** The agent's own name where a paged row already said it, else its kind. */
export function agentNameOf(row: ShownActivity, known: ReadonlyMap<string, string>): string {
  return row.agentName ?? known.get(row.agent) ?? row.agent;
}
