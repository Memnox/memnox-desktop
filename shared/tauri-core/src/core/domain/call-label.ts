import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';

/**
 * "Allow from now on": the daemon runs the call once and puts a narrow rule on a card to place and
 * sign. The runtime takes the word on a confirm beside the three in `HOLD_ANSWER`, which does not list it.
 */
export const FROM_NOW_ON = 'always';

/** Every answer a held call takes from a button here, the Mac's `HoldAnswer` with `always`. */
export type HeldAnswer = HoldAnswer | typeof FROM_NOW_ON;

/** How every label names the computer the app runs on. */
export const THIS_COMPUTER = 'this computer';
const SOME_AGENT = 'an agent';

/** Undefined for nothing but spaces, so a blank name never makes "on ". */
export function trimmed(text: string | undefined): string | undefined {
  const kept = text?.trim();
  return kept === undefined || kept === '' ? undefined : kept;
}

/** One label for a held call wherever it shows: "codex on this computer". Ported from the Mac's `CallLabel`. */
export function callLabel(agent: string | undefined, machine: string = THIS_COMPUTER): string {
  return `${trimmed(agent) ?? SOME_AGENT} on ${machine}`;
}

/** What the consent prompt says it is for, so the person answers knowing whose call and how far the yes reaches. */
export function consentReason(label: string, what: string | undefined, answer: HeldAnswer): string {
  const reach = REACH[answer](label);
  const phrase = trimmed(what);
  if (phrase === undefined) return reach;
  // A full stop inside the prompt's sentence reads as the end of it, so the last one goes.
  return `${reach}: ${phrase.endsWith('.') ? phrase.slice(0, -1) : phrase}`;
}

const REACH: Record<HeldAnswer, (label: string) => string> = {
  [HOLD_ANSWER.ONCE]: (label) => `allow ${label} once`,
  [HOLD_ANSWER.SESSION]: (label) => `allow ${label} for this session`,
  [HOLD_ANSWER.DENY]: (label) => `deny ${label}`,
  [HOLD_ANSWER.EDIT]: (label) => `send ${label} back to fix its command`,
  [FROM_NOW_ON]: (label) => `allow ${label} now, and put a rule for from now on to you`,
};
