import type { BackupSummary } from '@memnox/core/wire';

/** The shortest passphrase the runtime seals a backup under, so the form says so before it asks. */
export const SHORTEST_PASSPHRASE = 10;

/** What the passphrase fields say before Create or Restore is sent, or undefined when they will do. */
export function passphraseProblem(passphrase: string, again: string | undefined): string | undefined {
  if (passphrase.length < SHORTEST_PASSPHRASE) return `Use at least ${SHORTEST_PASSPHRASE} characters.`;
  if (again !== undefined && again !== passphrase) return 'The two passphrases differ, so type it the same both times.';
  return undefined;
}

/** "memnox-backup-2026-10-30.txt", named by the day it was made so a folder of them sorts. */
export function archiveFileName(createdAt: string): string {
  const day = /^\d{4}-\d{2}-\d{2}/.exec(createdAt);
  return `memnox-backup-${day === null ? 'undated' : day[0]}.txt`;
}

/** What an archive holds, in a line, before anything is put back. */
export function summaryLine(summary: Pick<BackupSummary, 'files' | 'ledger'>): string {
  const files = summary.files.length === 1 ? '1 file' : `${summary.files.length} files`;
  return summary.ledger ? `${files} and the ledger.` : `${files}, without the ledger.`;
}

/** Said once a restore was read: nothing is put back until the person signs it on the island. */
export function restoreWaitsLine(keyTitle: string): string {
  return `Nothing is put back yet. It waits for your signature with ${keyTitle} on the island, and then the setup in this backup replaces what is here.`;
}

/** The ledger rides along only to a computer that has none, which the switch says before it is turned on. */
export const LEDGER_LINE = 'It is only ever put back on a computer that has no ledger of its own.';
