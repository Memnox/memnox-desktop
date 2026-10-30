import { describe, expect, it } from 'vitest';
import { Backup } from '../src/core/application/backup';
import { RequestIds } from '../src/core/application/request-ids';
import { archiveFileName, passphraseProblem, restoreWaitsLine, summaryLine } from '../src/core/domain/backup-lines';
import { ScriptedDaemon } from './doubles';

const summary = { createdAt: '2026-10-30T12:00:00.000Z', files: ['rules.toml', 'hub.json'], ledger: true };

describe('the wording of a backup', () => {
  it('asks for ten characters, typed the same twice', () => {
    expect(passphraseProblem('short', 'short')).toBe('Use at least 10 characters.');
    expect(passphraseProblem('long enough!', 'long enough?')).toBe('The two passphrases differ, so type it the same both times.');
    expect(passphraseProblem('long enough!', 'long enough!')).toBeUndefined();
    expect(passphraseProblem('long enough!', undefined)).toBeUndefined();
  });

  it('names the file by its day and says what it holds', () => {
    expect(archiveFileName(summary.createdAt)).toBe('memnox-backup-2026-10-30.txt');
    expect(summaryLine(summary)).toBe('2 files and the ledger.');
    expect(summaryLine({ files: ['a'], ledger: false })).toBe('1 file, without the ledger.');
    expect(restoreWaitsLine('Windows Hello')).toContain('signature with Windows Hello on the island');
  });
});

describe('the backup use case', () => {
  it('hands back the sealed archive and what it holds, sending the ledger switch', async () => {
    const daemon = new ScriptedDaemon({ 'backup-create': (request) => [{ id: request.id, ok: true, backupArchive: 'sealed', backupSummary: summary }] });
    const made = await new Backup(daemon, new RequestIds()).create('a long passphrase', true);
    expect(made).toEqual({ kind: 'done', archive: 'sealed', summary });
    expect(daemon.sent('backup-create')[0]).toMatchObject({ backupPassphrase: 'a long passphrase', backupLedger: true });
  });

  it('proposes a restore rather than putting anything back, and passes a refusal on', async () => {
    const daemon = new ScriptedDaemon({ 'backup-restore': (request) => [{ id: request.id, ok: true, proposed: 'prp_2', backupSummary: summary }] });
    expect(await new Backup(daemon, new RequestIds()).restore(' sealed\n', 'a long passphrase')).toEqual({ kind: 'proposed', id: 'prp_2', summary });
    expect(daemon.sent('backup-restore')[0]).toMatchObject({ backupArchive: 'sealed' });
    const wrong = new ScriptedDaemon({ 'backup-restore': (request) => [{ id: request.id, ok: false, error: 'That passphrase does not open this backup.' }] });
    expect(await new Backup(wrong, new RequestIds()).restore('sealed', 'a long passphrase')).toEqual({ kind: 'failed', why: 'That passphrase does not open this backup.' });
    expect((await new Backup(new ScriptedDaemon(), new RequestIds()).create('a long passphrase', false)).kind).toBe('failed');
  });
});
