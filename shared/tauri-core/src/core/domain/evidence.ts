import { DELIVERY, type Delivery } from '@memnox/core/wire';

/**
 * What may be claimed about an action, from what was read back after it, ported from the Mac's `Evidence`:
 * nothing is called done that was not seen, and a send nobody could check is said to be unchecked. The
 * reading back itself waits on screen sight (J3); these rules are ready for it.
 */

/** Enough of the words to find the line they landed on, short enough that a wrap never splits it. */
const PROBE_LENGTH = 24;
/** Lines shown above the one the words landed on, so the card shows where they went. */
const EXCERPT_CONTEXT = 2;

/** What was checked after an action, and what was seen there, as a card shows it. */
export interface EvidenceProof {
  readonly checked: string;
  readonly seen?: string;
}

function squeezed(text: string): string {
  return text.replace(/\s+/gu, '');
}

function occurrences(needle: string, haystack: string): number {
  let count = 0;
  for (let at = haystack.indexOf(needle); at !== -1; at = haystack.indexOf(needle, at + needle.length)) count += 1;
  return count;
}

/**
 * Whether words typed into a target show there once more than they did before, ignoring how the target
 * wrapped or spaced them, so an identical instruction sent earlier never counts as this one.
 */
export function landed(text: string, before: string, after: string): boolean {
  const needle = squeezed(text);
  if (needle === '') return false;
  return occurrences(needle, squeezed(after)) > occurrences(needle, squeezed(before));
}

/** The last of the target's text around where the words went, enough to show on a card as what was seen. */
export function excerpt(text: string, around: string): string {
  const lines = text.split('\n').filter((line) => line !== '');
  if (lines.length === 0) return '';
  const probe = squeezed(around.slice(0, PROBE_LENGTH));
  let hit = lines.length - 1;
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (squeezed(lines[index] ?? '').includes(probe)) {
      hit = index;
      break;
    }
  }
  return lines.slice(Math.max(0, hit - EXCERPT_CONTEXT), hit + 1).join('\n');
}

/** Said by the app itself only when the daemon never heard the result, since the brain says it otherwise. */
export function unheard(outcome: Delivery, otherwise: string): string | undefined {
  switch (outcome) {
    case DELIVERY.VERIFIED:
    case DELIVERY.TYPED:
      return undefined;
    case DELIVERY.WAITING:
      return 'I kept it for its next prompt rather than take your window.';
    default:
      return otherwise;
  }
}

/** The proof as a card shows it: what was checked, then what was seen. */
export function proofCard(proof: EvidenceProof): string {
  return proof.seen === undefined || proof.seen === '' ? `Checked ${proof.checked}.` : `Checked ${proof.checked}:\n${proof.seen}`;
}
