import { DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';
import { awaitsAnswer } from './announcing';

/**
 * Which events reach the island from each machine, ported from the Mac's `MachineEvents`. The chosen one is
 * heard in full, since the voice and the session views talk to it; the others still bring what waits on the
 * person, so a held call is never missed because another machine was picked.
 */
export function deliversFrom(event: DaemonEvent, chosen: boolean, thisComputer: boolean): boolean {
  if (chosen) return true;
  switch (event.kind) {
    case DAEMON_EVENT.HELD:
    case DAEMON_EVENT.SETTLED:
      return true;
    // This computer's own agents ask and tell here whatever the voice talks to.
    case DAEMON_EVENT.PROPOSAL:
    case DAEMON_EVENT.NOTICE:
      return thisComputer || awaitsAnswer(event);
    default:
      return false;
  }
}
