import type { CardExcerpt, CardFile, DisplayHost, TraceCard, WalkPage } from '@memnox/core/wire';

/**
 * The cards that float outside the island in the top left of the screen, ported from the Mac's
 * `Cards` and `CardPanel`: a summary read while the voice says it, a walk through the changed files,
 * and a trace as a waterfall. `Displays` routes each SHOW event to one; this says how it is shown.
 */
export type FloatingCard =
  | { readonly kind: 'summary'; readonly title: string; readonly text: string; readonly agent?: string; readonly files: readonly CardFile[]; readonly excerpt?: CardExcerpt; readonly sessionId?: string; readonly host?: DisplayHost }
  | { readonly kind: 'walk'; readonly title: string; readonly agent?: string; readonly pages: readonly WalkPage[]; readonly sessionId?: string; readonly host?: DisplayHost }
  | { readonly kind: 'trace'; readonly title: string; readonly trace: TraceCard };

/** How long a floating card stays: a minute, or fifteen seconds once the pointer left; never while hovered. */
export const CARD_TIMING = { stayMs: 60_000, afterLeaveMs: 15_000, fadeInMs: 250, fadeOutMs: 300 } as const;

/** The card panel's place and size: 440 wide, 20 in from the top left, inside a 40 margin for its shadow. */
export const CARD_PANEL = { width: 440, inset: 20, margin: 40 } as const;

/** The voice's pace, about fourteen characters a second, and the shortest a page stays. */
const CHARACTERS_PER_SECOND = 14;
const SHORTEST_PAGE_SECONDS = 4;

/** How long a walk page stays before it turns on its own, as long as its note takes to say. */
export function pageSeconds(page: Pick<WalkPage, 'note'>): number {
  return Math.max(SHORTEST_PAGE_SECONDS, page.note.length / CHARACTERS_PER_SECOND);
}

/** "2 of 5", the walk's accessory. */
export function pagePosition(index: number, count: number): string {
  return `${index + 1} of ${count}`;
}

/** A trace's subtitle, how many steps it holds, so its size is read before its bars. */
export function traceSubtitle(steps: number): string {
  return steps === 1 ? '1 step' : `${steps} steps`;
}

/** Deeper steps stop indenting at four, so a long chain still leaves room for its name. */
const DEEPEST_INDENT = 4;
const INDENT_STEP = 12;
/** Even an instant step keeps a bar wide enough to see. */
const SHORTEST_BAR = 3;

/** Where one trace row's bar sits on a track of this width, and how far its name is indented. */
export function traceBar(row: TraceCard['rows'][number], totalMs: number, track: number): { offset: number; width: number; indent: number } {
  const total = Math.max(totalMs, 1);
  return {
    offset: (track * row.offsetMs) / total,
    width: Math.max(SHORTEST_BAR, (track * row.durationMs) / total),
    indent: Math.min(row.depth, DEEPEST_INDENT) * INDENT_STEP,
  };
}

/** The colour a trace bar takes: red for an error, amber for a refusal, blue at the top and green beneath. */
export function traceTone(row: Pick<TraceCard['rows'][number], 'status' | 'depth'>): 'destructive' | 'warm' | 'primary' | 'success' {
  if (row.status === 'error') return 'destructive';
  if (row.status === 'refused') return 'warm';
  return row.depth === 0 ? 'primary' : 'success';
}

/** The plain text badge, for a file with no extension. */
const PLAIN_BADGE = 'TXT';
const BADGE_LENGTH = 3;

/** A code excerpt's badge: its extension uppercased, at most three letters. */
export function extensionBadge(path: string): string {
  const name = path.split('/').pop() ?? path;
  const dot = name.lastIndexOf('.');
  const ext = dot <= 0 ? '' : name.slice(dot + 1);
  return ext === '' ? PLAIN_BADGE : ext.slice(0, BADGE_LENGTH).toUpperCase();
}

/** The open button's words on a card for a session: its app by name, or the session. */
export function openWords(host: DisplayHost | undefined, fallback: string): string {
  return host?.app === undefined ? fallback : `Open in ${host.app}`;
}
