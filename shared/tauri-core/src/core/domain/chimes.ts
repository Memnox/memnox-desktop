import { DAEMON_EVENT, HOLD_ANSWER, type DaemonEvent } from '@memnox/core/wire';

/**
 * A short sound at a moment the person should notice without looking, ported from the Mac's `Cue`:
 * what happened is heard before a word of it is said. The two the voice plays itself, listening and
 * sent, are named here too so every port plays from one list.
 */
export type Cue = 'listening' | 'sent' | 'held' | 'allowed' | 'declined' | 'done' | 'failed' | 'settled' | 'closed';

export const CUES: readonly Cue[] = ['listening', 'sent', 'held', 'allowed', 'declined', 'done', 'failed', 'settled', 'closed'];

/** Low enough that the ear and the recognizer never take a cue for the person talking, as the Mac's 0.35. */
export const CHIME_VOLUME = 0.35;

/**
 * The cue an event from the live feed plays, or none. A held call chimes as it arrives and a call
 * settled elsewhere purrs; a phone's events are left to the phone, so they make no sound here.
 */
export function cueForEvent(event: DaemonEvent, quiet: boolean): Cue | undefined {
  if (quiet) return undefined;
  switch (event.kind) {
    case DAEMON_EVENT.HELD:
      return 'held';
    case DAEMON_EVENT.SETTLED:
      return 'settled';
    default:
      return undefined;
  }
}

/** How a press on a card ended, as the cue sees it. */
export type PressEnd = 'answered' | 'answered-elsewhere' | 'cancelled' | 'failed';

/**
 * The cue an answer by hand plays: an allow rings out, a deny pulls in, somebody else's earlier
 * answer purrs, a failure thuds, and a cancelled prompt says nothing since nothing happened.
 */
export function cueForAnswer(answer: string, end: PressEnd): Cue | undefined {
  switch (end) {
    case 'answered':
      return answer === HOLD_ANSWER.DENY ? 'declined' : 'allowed';
    case 'answered-elsewhere':
      return 'settled';
    case 'failed':
      return 'failed';
    case 'cancelled':
      return undefined;
  }
}

/** The cue a proposal card's answer plays: a sent draft or a placed rule is done, a declined one pulls in. */
export function cueForProposal(sent: boolean, end: PressEnd): Cue | undefined {
  if (end === 'answered') return sent ? 'done' : 'declined';
  return cueForAnswer(HOLD_ANSWER.ONCE, end);
}
