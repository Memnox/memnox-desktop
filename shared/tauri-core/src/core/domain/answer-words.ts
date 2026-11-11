import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';

/**
 * The words a held call is answered with, the same on the terminal, the console, the Mac, Windows, Linux and the
 * phone. Mirrors the Mac's `AnswerWords` and `memnox-runtime/docs/ux/contract.json`, whose copy at
 * `shared/ux/contract.json` is tested.
 */

/** The answers a card offers, the narrowest yes first and Deny last, so a hand reaching for the usual place never lands on the wrong one. */
export const ANSWER_ORDER: readonly HoldAnswer[] = [HOLD_ANSWER.ONCE, HOLD_ANSWER.SESSION, HOLD_ANSWER.DENY];

export const ANSWER_LABEL: Readonly<Record<HoldAnswer, string>> = {
  [HOLD_ANSWER.ONCE]: 'Allow once',
  [HOLD_ANSWER.SESSION]: 'Allow for this session',
  [HOLD_ANSWER.EDIT]: 'Edit the command first',
  [HOLD_ANSWER.DENY]: 'Deny',
};

/** What stays on screen once a call is decided. */
export const ANSWER_OUTCOME: Readonly<Record<HoldAnswer, string>> = {
  [HOLD_ANSWER.ONCE]: 'allowed once',
  [HOLD_ANSWER.SESSION]: 'allowed for this session',
  [HOLD_ANSWER.EDIT]: 'editing',
  [HOLD_ANSWER.DENY]: 'denied',
};

/** The answers that write a rule rather than decide one call, offered only where a rule can be signed. */
export const ALWAYS_ALLOW = 'Always allow';
export const ALWAYS_DENY = 'Always deny';
