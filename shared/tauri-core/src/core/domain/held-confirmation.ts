import { actionConfirmationMessage, confirmationMessage } from '@memnox/core/wire';

/**
 * The words a yes to a held call signs: the v4 message bound to the exact call when the daemon gave its
 * digest, and the older one for a daemon that gave none, which still verifies it.
 */
export function heldConfirmation(subject: string, answer: string, actionDigest: string | undefined): string {
  return actionDigest === undefined ? confirmationMessage(subject, answer) : actionConfirmationMessage(subject, answer, actionDigest);
}
