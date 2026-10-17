import type { DaemonEvent } from '@memnox/core/wire';

/**
 * Whether an event belongs to a phone rather than to this computer's voice: stamped with the phone that
 * asked or the one holding the voice, or arriving while a phone holds it. This computer has no paired
 * device id of its own, so any stamp is a phone's. Ported from the Mac's `quietOnMac`.
 */
export function quietHere(event: DaemonEvent, phoneHolds: boolean): boolean {
  return phoneHolds || event.heardOn !== undefined || event.origin !== undefined;
}
