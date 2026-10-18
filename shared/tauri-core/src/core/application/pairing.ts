import { DAEMON_METHOD, grantMessage, pairMessage, type DaemonRequest, type DaemonResponse, type DeviceWire, type PairingPhone, type PairingWire } from '@memnox/core/wire';
import { ANOTHER_KEY_LINE } from '../domain/key-status';
import { DRIVE_CAPABILITY, PairingLines, stillPaired, type PhoneStep } from '../domain/pairing-lines';
import { Observed } from './observed';
import type { ConfirmKey } from './ports/confirm-key';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import { NO_KEY_LINE, type Signer } from './signer';

/** How a signed request went: done, the prompt cancelled so nothing was sent, or refused with why. */
export type DeviceChange = { kind: 'done' } | { kind: 'cancelled' } | { kind: 'refused'; why: string };

/** Pairing states after which nothing more comes for a pairing. */
const OVER = new Set(['paired', 'declined', 'expired']);

/**
 * Pairs a phone with this computer and looks after the phones paired, ported from the Mac's `Pairing` and the
 * phone half of `SetupModel`: the daemon decides and keeps them, this only carries the person's answers, and
 * every yes that widens what a phone can do is signed with the confirm key.
 */
export class PhonePairing extends Observed {
  private current: PhoneStep = { kind: 'idle' };
  private pairingId: string | undefined;
  private phones: readonly DeviceWire[] = [];

  constructor(
    private readonly link: DaemonLink,
    private readonly signer: Signer,
    private readonly key: ConfirmKey,
    private readonly ids: RequestIds,
    /** Whether this computer is connected to a workspace, asked before a phone pairs; undefined when unknown. */
    private readonly machineConnected: () => Promise<boolean | undefined>,
    /** What to call this computer on the phone. */
    private readonly computerName: () => string | undefined = () => undefined,
  ) {
    super();
  }

  get step(): PhoneStep {
    return this.current;
  }

  get devices(): readonly DeviceWire[] {
    return this.phones;
  }

  /** Opens a pairing and shows its QR, or the daemon's reason when it will not open one. */
  async pair(): Promise<void> {
    this.stopWatching();
    this.set({ kind: 'opening' });
    if ((await this.machineConnected()) === false) return this.fail(PairingLines.connectFirst);
    const name = this.computerName();
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.PAIR_BEGIN, ...(name !== undefined ? { name } : {}) });
    if (response === undefined) return this.fail(PairingLines.unreachable);
    const invite = response.pairing;
    if (response.outcome !== 'pairing' || invite?.qr === undefined) return this.fail(refusal(response, PairingLines.refused));
    this.pairingId = invite.id;
    this.set({ kind: 'showing', qr: invite.qr });
    void this.watch(invite.id);
  }

  /** The person's yes once the digits match: the key signs the pairing and the phone's key, and a cancel sends nothing. */
  async approve(): Promise<void> {
    const step = this.current;
    const id = this.pairingId;
    if (step.kind !== 'checking' || id === undefined) return;
    this.set({ kind: 'approving', phone: step.phone });
    const signed = await this.signed(pairMessage(id, step.phone.fingerprint), `pair ${step.phone.name}, showing ${step.phone.code}`);
    if (signed.kind === 'cancelled') return this.set({ kind: 'checking', phone: step.phone });
    if (signed.kind !== 'signed') return this.fail(signed.kind === 'refused' ? signed.why : PairingLines.refused);
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.PAIR_ACCEPT, pairingId: id, signature: signed.signature });
    if (response === undefined) return this.fail(PairingLines.unreachable);
    if (response.outcome === 'paired' && response.device !== undefined) return this.paired(response.device.name);
    this.fail(refusal(response, PairingLines.refused));
  }

  /** The person's no, or Cancel while the QR is up: the pairing ends and the row goes back to Pair. */
  async decline(): Promise<void> {
    const id = this.pairingId;
    this.stopWatching();
    this.set({ kind: 'idle' });
    if (id !== undefined) await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.PAIR_DECLINE, pairingId: id });
  }

  /** Every phone still paired, read again each time the page shows. */
  async loadDevices(): Promise<void> {
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.DEVICES_LIST });
    this.phones = (response?.devices ?? []).filter(stillPaired);
    this.changed();
  }

  /** Takes a phone's access away, unsigned since it only narrows what can reach this computer. */
  async revoke(device: DeviceWire): Promise<DeviceChange> {
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.DEVICE_REVOKE, deviceId: device.id });
    await this.loadDevices();
    return response?.outcome === 'revoked' ? { kind: 'done' } : { kind: 'refused', why: refusal(response, PairingLines.unreachable) };
  }

  /** On signs the grant of driving, since it widens what the phone can do; off goes unsigned and ends any drive. */
  async letDrive(device: DeviceWire, on: boolean): Promise<DeviceChange> {
    let change: DeviceChange;
    if (on) {
      const signed = await this.signed(grantMessage(device.id, DRIVE_CAPABILITY), `let ${device.name} act on this computer`);
      if (signed.kind !== 'signed') change = signed;
      else {
        const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.DEVICE_GRANT, deviceId: device.id, capability: DRIVE_CAPABILITY, signature: signed.signature });
        change = response?.outcome === 'granted' ? { kind: 'done' } : { kind: 'refused', why: refusal(response, PairingLines.unreachable) };
      }
    } else {
      const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.DEVICE_UNGRANT, deviceId: device.id, capability: DRIVE_CAPABILITY });
      change = response?.outcome === 'ungranted' ? { kind: 'done' } : { kind: 'refused', why: refusal(response, PairingLines.unreachable) };
    }
    await this.loadDevices();
    return change;
  }

  /** Where the pairing stands each time it changes, until it is paired, declined or expired. */
  private async watch(id: string): Promise<void> {
    try {
      for await (const response of this.link.stream({ id: this.ids.next(), method: DAEMON_METHOD.PAIR_PENDING, pairingId: id })) {
        if (id !== this.pairingId) return;
        const invite = response.pairing;
        if (invite === undefined) continue;
        this.moved(invite);
        if (invite.state !== undefined && OVER.has(invite.state)) return;
      }
    } catch {
      // Lost below, the same as a feed that closed.
    }
    this.lost(id);
  }

  private moved(invite: PairingWire): void {
    switch (invite.state) {
      case 'answered': {
        // Once the key's prompt is up the row stays on it, whatever else arrives.
        if (this.current.kind === 'approving') return;
        const phone = invite.phone;
        if (phone?.code !== undefined) this.set({ kind: 'checking', phone: phone as PairingPhone });
        return;
      }
      case 'paired':
        return this.paired(invite.phone?.name ?? '');
      case 'declined':
        return this.fail(PairingLines.declined);
      case 'expired':
        return this.fail(PairingLines.expired);
      default:
        return;
    }
  }

  /** The daemon stopped answering about a pairing still open, so the row offers to try again. */
  private lost(id: string): void {
    if (id !== this.pairingId) return;
    if (this.current.kind === 'showing' || this.current.kind === 'checking') this.fail(PairingLines.unreachable);
  }

  private paired(name: string): void {
    if (this.current.kind === 'paired') return;
    this.stopWatching();
    this.set({ kind: 'paired', name });
    void this.loadDevices();
  }

  private fail(why: string): void {
    this.stopWatching();
    this.set({ kind: 'failed', why });
  }

  private stopWatching(): void {
    this.pairingId = undefined;
  }

  /** A signature from the person, after the key is registered, since one the daemon does not trust is refused late. */
  private async signed(message: string, reason: string): Promise<{ kind: 'signed'; signature: string } | { kind: 'cancelled' } | { kind: 'refused'; why: string }> {
    const status = await this.signer.registerKey();
    if (status.kind === 'another-key') return { kind: 'refused', why: ANOTHER_KEY_LINE };
    if (status.kind === 'no-key') return { kind: 'refused', why: NO_KEY_LINE };
    const signature = await this.key.sign(message, reason).catch(() => undefined);
    return signature === undefined ? { kind: 'cancelled' } : { kind: 'signed', signature };
  }

  private ask(request: DaemonRequest): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, request).catch(() => undefined);
  }

  private set(step: PhoneStep): void {
    this.current = step;
    this.changed();
  }
}

/** The daemon's own words for a no, so the person hears why rather than a code. */
function refusal(response: DaemonResponse | undefined, fallback: string): string {
  for (const words of [response?.reason, response?.error]) if (words !== undefined && words !== '') return words;
  return fallback;
}
