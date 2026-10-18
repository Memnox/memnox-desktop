import type { DaemonEvent } from '@memnox/core/wire';

/**
 * This computer's device id on each server it paired with, so an event a server raised for this computer's own
 * ask is said here rather than left for a phone. Set by the composition root whenever the servers change.
 * Ported from the Mac's `OwnDevices`.
 */
export const OWN_DEVICES = {
  ids: new Set<string>() as ReadonlySet<string>,
  set(ids: Iterable<string>): void {
    this.ids = new Set(ids);
  },
};

/**
 * Whether an event belongs to a phone rather than to this computer's voice: stamped with the phone that
 * asked or the one holding the voice, or arriving while a phone holds it. A stamp with one of this
 * computer's own device ids is this computer speaking, not a phone. Ported from the Mac's `quietOnMac`.
 */
export function quietHere(event: DaemonEvent, phoneHolds: boolean, own: ReadonlySet<string> = OWN_DEVICES.ids): boolean {
  if (phoneHolds) return true;
  return [event.heardOn?.deviceId, event.origin?.deviceId].some((id) => id !== undefined && !own.has(id));
}
