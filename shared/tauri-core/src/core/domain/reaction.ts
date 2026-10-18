import { DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';
import type { Reaction } from './orb-motion';

/**
 * The gesture the orb and a session's logo make at an event, ported from the Mac's `reaction(to:)`. It is
 * read from the daemon's facts and never from words, so it celebrates only work the ledger shows was checked.
 */
export function reactionTo(event: DaemonEvent): Reaction | undefined {
  if (event.kind === DAEMON_EVENT.PAUSED) return 'stumble';
  if (event.kind !== DAEMON_EVENT.NOTICE) return undefined;
  switch (event.notice) {
    case 'finished':
      // A pass followed by more writes, or no run at all, proves nothing, so it is only marked.
      return event.tests === 'passed' ? 'burst' : event.tests === 'failed' ? 'stumble' : 'settle';
    case 'committed':
    case 'pushed':
    case 'signed-in':
    // Seen as it comes and goes, so a session appearing or closing is never only in a list.
    case 'started':
    case 'closed':
      return 'settle';
    case 'collision':
    case 'gone':
    case 'sign-in-stalled':
      return 'stumble';
    default:
      return undefined;
  }
}
