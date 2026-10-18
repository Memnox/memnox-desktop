import type { DeviceWire, PairingPhone } from '@memnox/core/wire';

/** What the phone row says as a pairing goes, ported from the Mac's `PairingLines`. */
export const PairingLines = {
  /** "Your iPhone is paired", or the name alone when it already says whose it is. */
  paired(phone: string): string {
    const name = phone.trim();
    if (name === '') return 'Your phone is paired.';
    const owned = ["'s ", '’s '].some((mark) => name.includes(mark));
    return owned ? `${name} is paired.` : `Your ${name} is paired.`;
  },
  declined: 'The phone was not paired.',
  expired: 'The code ran out before a phone used it. Pair again when your phone is ready.',
  unreachable: 'Memnox on this computer is not answering, so a phone cannot pair yet.',
  refused: 'Memnox would not open a pairing just now.',
  connectFirst:
    'This computer is not connected to a workspace yet, which is what carries the phone to it. Connect it on the Account page, then pair again.',
} as const;

/** Where pairing a phone stands, from the QR to the digits the person checks to the result, as `PhoneStep`. */
export type PhoneStep =
  | { kind: 'idle' }
  | { kind: 'opening' }
  | { kind: 'showing'; qr: string }
  /** A phone reached the pairing and its digits wait on the person. */
  | { kind: 'checking'; phone: PairingPhone }
  /** The key's prompt is up for the yes. */
  | { kind: 'approving'; phone: PairingPhone }
  | { kind: 'paired'; name: string }
  | { kind: 'failed'; why: string };

/** The capability that lets a phone drive this computer, which only a signed grant widens to. */
export const DRIVE_CAPABILITY = 'mac';

/** A phone still paired, which a revoked one is not. */
export function stillPaired(device: DeviceWire): boolean {
  return device.revokedAt === undefined;
}

export function drives(device: DeviceWire): boolean {
  return device.capabilities.includes(DRIVE_CAPABILITY);
}

/** What it may do, in the capabilities' own words, as the Mac's `DeviceRow` says it. */
export function deviceCaption(device: DeviceWire): string {
  return device.capabilities.length === 0 ? 'Paired' : `Can ${device.capabilities.join(', ')}`;
}
