import type { PairedServer } from '../../domain/paired-machines';
import type { PairingFailure } from '../../domain/server-pairing-lines';

/** How a pairing came out: the server, kept, or why not. */
export type Paired = { kind: 'paired'; server: PairedServer } | { kind: 'failed'; why: PairingFailure };

/**
 * Runs the pairing ceremony with the server in a pasted link and keeps the result: the XXpsk0 handshake, the
 * proof signed by the confirm key, and the wait for the person to type the digits there. The keys it makes and the
 * relay token it is given never leave the adapter. Ported from the Mac's `Pairer` and `PairedStore` together.
 */
export interface Pairer {
  /** Calls `code` with the six digits as soon as the handshake ends, then waits for the server's verdict. */
  pair(link: string, name: string, code: (digits: string) => void): Promise<Paired>;
  /** Every server kept, oldest pairing first. */
  servers(): Promise<readonly PairedServer[]>;
  /** Forgets a server here and closes its session. */
  forget(machineId: string): Promise<void>;
}
