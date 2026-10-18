import { isInvitationError, readInvitation } from '../domain/pairing-invitation';
import type { PairedServer } from '../domain/paired-machines';
import { ServerPairingLines } from '../domain/server-pairing-lines';
import type { Diary } from './diary';
import { Observed } from './observed';
import type { Pairer } from './ports/pairer';

/** Where connecting to a server stands, from the pasted link to the digits the person types there to the result. */
export type ServerStep =
  | { kind: 'idle' }
  /** The handshake is running over the relay. */
  | { kind: 'pairing' }
  /** Both ends have the digits, and the server waits for the person to type them into memnox pair. */
  | { kind: 'showing-code'; code: string }
  | { kind: 'connected'; name: string }
  | { kind: 'failed'; why: string };

/**
 * Pairs this computer with a server over the relay, from the memnox://pair link `memnox pair` printed there, and
 * keeps the servers paired. The server decides, by the person typing the digits shown here; this only carries the
 * handshake and keeps the result. Ported from the Mac's `ServerPairing` and the server half of `SetupModel`.
 */
export class ServerPairing extends Observed {
  private current: ServerStep = { kind: 'idle' };
  private kept: readonly PairedServer[] = [];

  constructor(
    private readonly pairer: Pairer,
    /** What to call this computer on the server. */
    private readonly name: () => string,
    /** The word for the system's prompt, Windows Hello or the password, for a cancelled one. */
    private readonly keyWord: string,
    /** Told when a server is paired or forgotten, so the island opens or drops its link. */
    private readonly serversChanged: () => void = () => undefined,
    private readonly now: () => number = Date.now,
    private readonly diary?: Diary,
  ) {
    super();
  }

  get step(): ServerStep {
    return this.current;
  }

  get servers(): readonly PairedServer[] {
    return this.kept;
  }

  /** The servers as kept, read each time the page shows, so one paired from elsewhere appears. */
  async load(): Promise<void> {
    this.kept = await this.pairer.servers().catch(() => this.kept);
    this.changed();
  }

  /** Pairs with the server in the pasted link, showing the six digits to type there the moment both ends have them. */
  async connect(link: string): Promise<void> {
    const pasted = link.trim();
    if (pasted === '' || this.current.kind === 'pairing' || this.current.kind === 'showing-code') return;
    const invitation = readInvitation(pasted, this.now());
    if (isInvitationError(invitation)) return this.set({ kind: 'failed', why: ServerPairingLines.failed(invitation, this.keyWord) });
    this.diary?.note(`pairing with the server ${invitation.machine}`);
    this.set({ kind: 'pairing' });
    const paired = await this.pairer
      .pair(pasted, this.name(), (code) => {
        if (this.current.kind === 'pairing') this.set({ kind: 'showing-code', code });
      })
      .catch(() => ({ kind: 'failed' as const, why: { kind: 'broken' as const } }));
    if (paired.kind === 'failed') {
      this.diary?.note(`pairing with ${invitation.machine} stopped: ${paired.why.kind}`);
      this.set({ kind: 'failed', why: ServerPairingLines.failed(paired.why, this.keyWord) });
    } else {
      this.set({ kind: 'connected', name: paired.server.machine });
    }
    await this.load();
    this.serversChanged();
  }

  /** Forgets a server here; the server keeps this computer's device record until somebody revokes it there. */
  async forget(machineId: string): Promise<void> {
    await this.pairer.forget(machineId).catch(() => undefined);
    this.diary?.note(`forgot the server ${machineId}`);
    await this.load();
    this.serversChanged();
  }

  private set(step: ServerStep): void {
    this.current = step;
    this.changed();
  }
}
