import { HOLD_ANSWER, PROPOSAL_ANSWER, type DaemonResponse } from '@memnox/core/wire';

/** How the daemon begins an outcome for a call or proposal answered before. */
const ALREADY = 'already ';
/** The word a held call's outcome puts before the answer, which a proposal's leaves out. */
const ANSWERED = 'answered';
/** How the daemon ends the refusal for a held call whose record is gone. */
const NO_LONGER_HELD = ' is no longer held';

const PHRASES: Record<string, string> = {
  [HOLD_ANSWER.DENY]: 'denied',
  [HOLD_ANSWER.ONCE]: 'allowed once',
  [HOLD_ANSWER.SESSION]: 'allowed for the session',
  [PROPOSAL_ANSWER.CONFIRMED]: 'confirmed',
  [PROPOSAL_ANSWER.DECLINED]: 'declined',
};

/**
 * The answer that settled a call before this one reached the daemon. The first answer is what
 * happened, so a second press reports it rather than looking like it took. Ported from the Mac.
 */
export class EarlierAnswer {
  private constructor(
    /** The daemon's word for the first answer, undefined when it no longer says which. */
    readonly word: string | undefined,
  ) {}

  /** Undefined when this answer was the one that counted. */
  static from(response: DaemonResponse | undefined): EarlierAnswer | undefined {
    if (response === undefined) return undefined;
    const { ok, outcome, error } = response;
    if (ok && outcome !== undefined && outcome.startsWith(ALREADY)) {
      let rest = outcome.slice(ALREADY.length).trim();
      if (rest.startsWith(ANSWERED)) rest = rest.slice(ANSWERED.length).trim();
      return new EarlierAnswer(rest === '' ? undefined : rest);
    }
    // Answered and released already, so the daemon no longer knows which answer it was.
    if (!ok && error !== undefined && error.endsWith(NO_LONGER_HELD)) return new EarlierAnswer(undefined);
    return undefined;
  }

  matches(chosen: string): boolean {
    return this.word === chosen;
  }

  /** What the person reads instead of the outcome of their own press. */
  get line(): string {
    const phrase = this.word === undefined ? undefined : PHRASES[this.word];
    // Without the word it may have timed out rather than been answered, so it claims neither.
    if (phrase === undefined) return 'That was settled before your answer arrived, so nothing changed.';
    return `That was already answered elsewhere: it was ${phrase}.`;
  }
}
