/**
 * Which issue a session concerns, as the workspace matched it: exactly, against what a connected tracker delivered,
 * and never by resemblance. Read from `GET v1/workspaces/:ws/work-correlations`; mirrors the console's
 * `lib/work-correlations.ts`, so a session reads the same on both.
 */

/** The three things a person is told; a session that named no issue shows nothing at all. */
export type WorkShown = 'linked' | 'unverified' | 'ambiguous';

export interface WorkCorrelation {
  readonly id: string;
  readonly sessionId: string;
  readonly source: string;
  readonly state: string;
  readonly lateMatch: boolean;
  readonly claim?: string;
  readonly matches?: number;
  readonly visible: boolean;
  readonly item?: { readonly provider: string; readonly label: string; readonly url: string };
}

const SOURCE_WORDS: Readonly<Record<string, string>> = {
  assignment: 'assignment',
  provider_link: 'pull request',
  handoff: 'handoff',
  sdk: 'SDK',
  automation: 'automation',
  mcp_target: 'MCP',
  branch: 'branch',
  commit: 'commit',
  prompt: 'prompt',
};

const UNVERIFIED_REASON: Readonly<Record<string, string>> = {
  pending: 'Waiting for the tracker to deliver it.',
  expired: 'No tracker delivered it within a day.',
  unverifiable: 'Its tracker is no longer connected.',
};

export const WorkCorrelationLines = {
  heading: 'Issue',
  hidden: 'An item you cannot see',
  lateMatch: 'A matching item arrived later. Confirm it in the console.',
  explain: 'Memnox reads the issue key in the branch, commits or agent, and links it only when exactly one connected tracker has that issue. A link is not an assignment.',
  via: (source: string): string => `Linked via ${SOURCE_WORDS[source] ?? source}`,
  unverified: (claim: string): string => `${claim}, not verified`,
  ambiguous: (claim: string, matches: number): string => `${claim} matches ${matches} trackers, not linked`,
} as const;

/** What a correlation shows as, or nothing for one a newer claim replaced or a person removed. */
export function shownAs(correlation: WorkCorrelation): WorkShown | undefined {
  if (correlation.state === 'linked') return 'linked';
  if (correlation.state === 'ambiguous') return 'ambiguous';
  if (correlation.state === 'pending' || correlation.state === 'expired' || correlation.state === 'unverifiable') return 'unverified';
  return undefined;
}

/** The one line a session shows for a correlation. */
export function workLabel(correlation: WorkCorrelation): string {
  const claim = correlation.claim ?? 'A claim';
  const shown = shownAs(correlation);
  if (shown === 'linked') return correlation.visible && correlation.item !== undefined ? correlation.item.label : WorkCorrelationLines.hidden;
  if (shown === 'ambiguous') return WorkCorrelationLines.ambiguous(claim, correlation.matches ?? 2);
  return WorkCorrelationLines.unverified(claim);
}

/** Why it reads as it does: what a link rests on, or why a claim is not linked. */
export function workReason(correlation: WorkCorrelation): string | undefined {
  const shown = shownAs(correlation);
  if (shown === 'linked') return WorkCorrelationLines.via(correlation.source);
  if (shown === 'unverified') return correlation.lateMatch ? WorkCorrelationLines.lateMatch : UNVERIFIED_REASON[correlation.state];
  return undefined;
}

/** The ones a session shows, one per claim, replaced and removed left out. */
export function forSession(all: readonly WorkCorrelation[], sessionId: string): WorkCorrelation[] {
  const kept: WorkCorrelation[] = [];
  for (const each of all) {
    if (each.sessionId !== sessionId || shownAs(each) === undefined) continue;
    if (!kept.some((seen) => seen.claim !== undefined && seen.claim === each.claim)) kept.push(each);
  }
  return kept;
}

/** The cloud's answer, each row read on its own so one it cannot read never hides the rest. */
export function readWorkCorrelations(body: unknown): WorkCorrelation[] {
  const list = isObject(body) && Array.isArray(body['correlations']) ? (body['correlations'] as unknown[]) : [];
  return list.flatMap((row) => {
    if (!isObject(row)) return [];
    const { id, sessionId, source, state, claim, matches, item } = row;
    if (typeof id !== 'string' || typeof sessionId !== 'string' || typeof source !== 'string' || typeof state !== 'string') return [];
    const linked =
      isObject(item) && typeof item['label'] === 'string' && typeof item['url'] === 'string' && typeof item['provider'] === 'string'
        ? { item: { provider: item['provider'], label: item['label'], url: item['url'] } }
        : {};
    return [
      {
        id,
        sessionId,
        source,
        state,
        lateMatch: row['lateMatch'] === true,
        visible: row['visible'] === true,
        ...(typeof claim === 'string' ? { claim } : {}),
        ...(typeof matches === 'number' ? { matches } : {}),
        ...linked,
      },
    ];
  });
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
