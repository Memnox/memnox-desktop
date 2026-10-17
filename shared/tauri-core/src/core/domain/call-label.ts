import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';

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
export function consentReason(label: string, what: string | undefined, answer: HoldAnswer): string {
  const reach = REACH[answer](label);
  const phrase = trimmed(what);
  if (phrase === undefined) return reach;
  // A full stop inside the prompt's sentence reads as the end of it, so the last one goes.
  return `${reach}: ${phrase.endsWith('.') ? phrase.slice(0, -1) : phrase}`;
}

const REACH: Record<HoldAnswer, (label: string) => string> = {
  [HOLD_ANSWER.ONCE]: (label) => `allow ${label} once`,
  [HOLD_ANSWER.SESSION]: (label) => `allow ${label} for this session`,
  [HOLD_ANSWER.DENY]: (label) => `deny ${label}`,
  [HOLD_ANSWER.EDIT]: (label) => `send ${label} back to fix its command`,
};
