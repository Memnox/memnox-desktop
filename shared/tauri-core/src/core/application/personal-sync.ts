import { PERSONAL_SYNC_METHOD, type DaemonRequest, type DaemonResponse, type PersonalSyncConflict, type PersonalSyncStatus, type SyncKeep } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How one press ended: done at once, proposed and waiting for a signature on the island, or refused. */
export type SyncOutcome = { kind: 'done' } | { kind: 'proposed'; id: string } | { kind: 'failed'; why: string };

/**
 * Personal sync as the runtime runs it. It holds no key and no rule: the runtime seals and syncs, and the
 * key moves between the person's machines only as a proposal signed on the island after they compared a fingerprint.
 */
export class PersonalSync extends Observed {
  private view: PersonalSyncStatus | undefined;
  private opened: readonly PersonalSyncConflict[] | undefined;
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get status(): PersonalSyncStatus | undefined {
    return this.view;
  }

  /** The conflict copies opened beside this machine's own, once asked for. */
  get conflicts(): readonly PersonalSyncConflict[] | undefined {
    return this.opened;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** What a press is still working on: `now`, a conflict's id, or a machine's, so its control can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_STATUS });
    this.failed = response === undefined || !response.ok;
    this.take(response);
  }

  syncNow(): Promise<SyncOutcome> {
    return this.press('now', { method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_NOW });
  }

  async loadConflicts(): Promise<SyncOutcome> {
    return this.press('conflicts', { method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_CONFLICTS });
  }

  /** Keeps one side; the conflict is gone from the list either way once the runtime answers. */
  async resolve(id: string, keep: SyncKeep): Promise<SyncOutcome> {
    const outcome = await this.press(id, { method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_RESOLVE, syncConflictId: id, syncKeep: keep });
    if (outcome.kind !== 'failed' && this.opened !== undefined) {
      this.opened = this.opened.filter((each) => each.id !== id);
      this.changed();
    }
    return outcome;
  }

  /** On the machine holding the key: proposes sealing it to a waiting machine whose fingerprint was compared. */
  offer(machineId: string, fingerprint: string): Promise<SyncOutcome> {
    return this.press(machineId, { method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_KEY_OFFER, syncMachineId: machineId, syncFingerprint: fingerprint });
  }

  /** On the new machine: proposes taking the key that arrived, once the same fingerprint was compared. */
  accept(fingerprint: string): Promise<SyncOutcome> {
    return this.press('accept', { method: PERSONAL_SYNC_METHOD.PERSONAL_SYNC_KEY_ACCEPT, syncFingerprint: fingerprint });
  }

  private async press(subject: string, fields: Omit<DaemonRequest, 'id'>): Promise<SyncOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    this.take(response);
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
    return { kind: 'done' };
  }

  private take(response: DaemonResponse | undefined): void {
    if (response?.personalSync !== undefined) this.view = response.personalSync;
    if (response?.syncConflicts !== undefined) this.opened = response.syncConflicts;
    this.changed();
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a personal sync method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
