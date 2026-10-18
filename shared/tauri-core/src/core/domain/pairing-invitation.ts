import { Base64URL, fromBase64, utf8 } from './base64url';

/** Why a pasted link is not a pairing this computer can use. */
export type InvitationError =
  /** Not a memnox://pair link at all. */
  | { kind: 'not-a-pairing-link' }
  | { kind: 'unreadable' }
  /** A newer server than this app understands. */
  | { kind: 'unsupported-version'; version: number }
  | { kind: 'expired' };

/** What a `memnox pair` link carries that the person is told about; its secrets are read again in Rust, where they are used. */
export interface PairingInvitation {
  readonly machineId: string;
  readonly machine: string;
  readonly relayUrl: string;
  readonly expiresAt: number;
}

/** The only link version this app reads. */
export const INVITATION_VERSION = 1;
const MAILBOX_BYTES = 16;
/** Noise keys and the PSK are all 32 bytes. */
const KEY_BYTES = 32;

interface WireInvitation {
  v: number;
  machineId: string;
  machine: string;
  relayUrl: string;
  mailbox: string;
  pairingToken: string;
  runtimeNoiseStatic: string;
  secret: string;
  expiresAt: string;
}

/** An ISO 8601 instant with or without fractional seconds, as epoch milliseconds, or undefined. */
export function readInstant(text: string): number | undefined {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(text)) return undefined;
  const at = Date.parse(text);
  return Number.isNaN(at) ? undefined : at;
}

/**
 * Reads a pasted link, refusing one that is malformed, from a newer server, or past its expiry at `now`.
 * It holds no lasting credential: the secret works for one handshake and the token for two minutes.
 * Ported from the Mac's `PairingInvitation`.
 */
export function readInvitation(link: string, now: number): PairingInvitation | InvitationError {
  const match = /^memnox:\/\/pair\/?\?(.*)$/.exec(link.trim());
  const payload = match?.[1]?.split('&').find((pair) => pair.startsWith('d='))?.slice(2);
  if (payload === undefined) return { kind: 'not-a-pairing-link' };
  const json = Base64URL.decode(payload);
  let wire: WireInvitation;
  try {
    if (json === undefined) return { kind: 'unreadable' };
    wire = JSON.parse(utf8(json)) as WireInvitation;
  } catch {
    return { kind: 'unreadable' };
  }
  if (wire.v !== INVITATION_VERSION) return typeof wire.v === 'number' ? { kind: 'unsupported-version', version: wire.v } : { kind: 'unreadable' };
  const expiresAt = typeof wire.expiresAt === 'string' ? readInstant(wire.expiresAt) : undefined;
  const usable =
    typeof wire.machineId === 'string' &&
    typeof wire.machine === 'string' &&
    typeof wire.relayUrl === 'string' &&
    /^wss?:\/\//.test(wire.relayUrl) &&
    Base64URL.decode(String(wire.mailbox))?.length === MAILBOX_BYTES &&
    fromBase64(String(wire.runtimeNoiseStatic))?.length === KEY_BYTES &&
    fromBase64(String(wire.secret))?.length === KEY_BYTES &&
    typeof wire.pairingToken === 'string' &&
    wire.pairingToken !== '' &&
    expiresAt !== undefined;
  if (!usable) return { kind: 'unreadable' };
  if (expiresAt <= now) return { kind: 'expired' };
  return { machineId: wire.machineId, machine: wire.machine, relayUrl: wire.relayUrl, expiresAt };
}

export function isInvitationError(read: PairingInvitation | InvitationError): read is InvitationError {
  return 'kind' in read;
}
