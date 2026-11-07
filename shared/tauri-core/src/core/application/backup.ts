import { BACKUP_METHOD, type BackupSummary, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How making a backup ended: the sealed archive and what it holds, or refused with why. */
export type BackupMade = { kind: 'done'; archive: string; summary: BackupSummary } | { kind: 'failed'; why: string };

/** How reading one back ended: proposed and waiting on a signature, with what it holds, or refused. */
export type BackupRead = { kind: 'proposed'; id: string; summary: BackupSummary } | { kind: 'failed'; why: string };

/**
 * Backing up what a person set up on this computer and putting it back. It holds no rule and no secret:
 * the runtime seals the archive under the passphrase, and a restore waits for a signature on the island.
 */
export class Backup {
  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {}

  async create(passphrase: string, ledger: boolean): Promise<BackupMade> {
    const response = await this.ask({ method: BACKUP_METHOD.BACKUP_CREATE, backupPassphrase: passphrase, backupLedger: ledger });
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.backupArchive === undefined || response.backupSummary === undefined) return { kind: 'failed', why: 'The runtime made no backup.' };
    return { kind: 'done', archive: response.backupArchive, summary: response.backupSummary };
  }

  async restore(archive: string, passphrase: string): Promise<BackupRead> {
    const response = await this.ask({ method: BACKUP_METHOD.BACKUP_RESTORE, backupArchive: archive.trim(), backupPassphrase: passphrase });
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.proposed === undefined || response.backupSummary === undefined) return { kind: 'failed', why: 'The runtime proposed nothing to put back.' };
    return { kind: 'proposed', id: response.proposed, summary: response.backupSummary };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: both callers pass a backup method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by the outcome, never thrown at the page.
      return undefined;
    }
  }
}
