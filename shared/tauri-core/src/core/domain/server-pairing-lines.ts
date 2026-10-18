import type { InvitationError } from './pairing-invitation';

/** Why pairing with a server stopped, in the kinds the Rust pairer names. */
export type PairingFailure =
  | InvitationError
  | { kind: 'wrong-machine' }
  | { kind: 'declined' }
  | { kind: 'cancelled' }
  | { kind: 'no-key' }
  | { kind: 'not-kept'; why?: string }
  | { kind: 'broken'; why?: string };

/**
 * What the Phones page says while this computer pairs with a server over the relay, ported from the Mac's
 * `ServerPairingLines` with "this Mac" said as "this computer". A server keeps no key of this computer's
 * to accept with, so the person accepts there by typing the digits this computer shows into memnox pair.
 */
export const ServerPairingLines = {
  typeCode: 'Type these six digits into memnox pair on the server.',
  meeting: 'Meeting the server through the relay.',
  unreachable: 'The relay could not be reached, or the server stopped answering. Check the connection and try again.',
  notKept: 'Paired, but this computer could not keep the server in its credential store, so pair again.',
  noKey: 'This computer has no key to prove itself with, so it cannot pair with a server.',
  thisComputer: 'This computer',

  connected(server: string): string {
    const name = server.trim();
    return name === '' ? 'Connected to your server.' : `Connected to ${name}.`;
  },

  failed(why: PairingFailure, keyWord: string): string {
    switch (why.kind) {
      case 'not-a-pairing-link':
        return 'That is not a Memnox pairing link. Paste the memnox://pair link that memnox pair printed.';
      case 'unreadable':
        return 'That pairing link could not be read. Run memnox pair again and paste the new link.';
      case 'unsupported-version':
        return 'That server runs a newer Memnox than this app. Update the app, then pair again.';
      case 'expired':
        return 'That link ran out. Run memnox pair again and paste the new link.';
      case 'wrong-machine':
        return 'The machine that answered is not the one in the link, so this computer stopped. Run memnox pair again.';
      case 'declined':
        return 'The server did not pair this computer.';
      case 'cancelled':
        return `${keyWord} was cancelled, so this computer did not pair.`;
      case 'no-key':
        return ServerPairingLines.noKey;
      case 'not-kept':
        return ServerPairingLines.notKept;
      case 'broken':
        return ServerPairingLines.unreachable;
    }
  },
};
