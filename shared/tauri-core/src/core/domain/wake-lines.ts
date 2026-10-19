/**
 * What it says when called, brief and composed, using the address they chose and never one guessed.
 * The first call in a while is greeted for the hour; any other is a word or two, and never the same
 * line twice running. Ported from `WakeLines.swift` and `WakeRest.swift`.
 */

/** Long enough apart that being called again is a fresh start, and earns a greeting. */
export const FRESH_AFTER_MS = 3 * 60 * 60 * 1_000;
/** How long their name rests once said, far longer than the title does. */
const NAME_RESTS_MS = 30 * 60 * 1_000;
const AFTERNOON_FROM = 12;
const EVENING_FROM = 17;

export type Pick = (choices: readonly string[]) => string | undefined;

const randomPick: Pick = (choices) => choices[Math.floor(Math.random() * choices.length)];

function trimmed(text: string | undefined): string | undefined {
  const value = text?.trim();
  return value === undefined || value === '' ? undefined : value;
}

function greetings(to: string | undefined, hour: number): string[] {
  const part = hour < AFTERNOON_FROM ? 'Good morning' : hour < EVENING_FROM ? 'Good afternoon' : 'Good evening';
  const named = to === undefined ? `${part}.` : `${part}, ${to}.`;
  return [`${named} Systems online. Memnox is ready.`, `${named} Let's see what your agents are up to.`, `${named} Your agents, your rules.`];
}

/** Never "Yes", since being called is not a question it was asked, and a "Yes" sounds like it agreed to something. */
function replies(to: string | undefined): string[] {
  if (to === undefined) return ['How may I help?', "I'm listening.", 'How may I assist?', 'What can I do for you?'];
  return [`How may I help, ${to}?`, `I'm listening, ${to}.`, `What can I do for you, ${to}?`, `How may I assist, ${to}?`];
}

export class WakeLines {
  private last: string | undefined;
  private namedAt: number | undefined;

  line(options: { address?: string; name?: string; hour: number; sinceLastCallMs: number | undefined; at?: number; pick?: Pick }): string {
    const { hour, sinceLastCallMs, at = Date.now(), pick = randomPick } = options;
    const title = trimmed(options.address);
    const known = trimmed(options.name);
    const name = known === title ? undefined : known;
    const fresh = sinceLastCallMs === undefined || sinceLastCallMs >= FRESH_AFTER_MS;
    const rested = this.namedAt === undefined || at - this.namedAt >= NAME_RESTS_MS;
    // The name only once they chose any address at all, since a name alone was never a choice of how to be called.
    const named = title !== undefined && name !== undefined && rested;
    const to = named ? name : title;
    const lines = fresh ? greetings(to, hour) : replies(to);
    const choices = lines.length > 1 ? lines.filter((line) => line !== this.last) : lines;
    const chosen = pick(choices) ?? lines[0] ?? '';
    this.last = chosen;
    if (named) this.namedAt = at;
    return chosen;
  }
}

/** How long listening for its name rests between rounds, so a recognizer failing again and again backs off. */
export const WAKE_REST = {
  afterWorkingMs: 300,
  afterFirstFailureMs: 1_000,
  longestMs: 30_000,
  growth: 2,
} as const;

export class WakeRest {
  private failuresInARow = 0;

  /** The rest before the next round, after one that ended on a failure or not. */
  after(failed: boolean): number {
    if (!failed) {
      this.failuresInARow = 0;
      return WAKE_REST.afterWorkingMs;
    }
    const rest = WAKE_REST.afterFirstFailureMs * WAKE_REST.growth ** this.failuresInARow;
    this.failuresInARow += 1;
    return Math.min(WAKE_REST.longestMs, rest);
  }
}
