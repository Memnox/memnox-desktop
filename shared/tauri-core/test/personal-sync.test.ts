import type { PersonalSyncConflict, PersonalSyncStatus } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { PersonalSync } from '../src/core/application/personal-sync';
import { RequestIds } from '../src/core/application/request-ids';
import {
  conflictCaption,
  conflictsLine,
  fingerprintGroups,
  keyWaitsLine,
  kindCount,
  lastSyncedLine,
  openedElsewhereLine,
  syncStateWord,
} from '../src/core/domain/personal-sync-lines';
import { ScriptedDaemon } from './doubles';

const ready: PersonalSyncStatus = {
  state: 'ready',
  said: 'Synced. Everything here is on your other machines.',
  keyId: 'k_1',
  lastSyncedAt: '2026-10-30T11:00:00Z',
  kinds: [
    { kind: 'servers', items: 3 },
    { kind: 'memory', items: 1 },
  ],
  conflicts: 1,
  skipped: [],
  openedElsewhere: ['github.com/acme/api'],
  waiting: [{ machineId: 'm_laptop', fingerprint: '12345 67890 11121 31415 16171 81920', sealed: false }],
};

const conflict: PersonalSyncConflict = { id: 'c_1', kind: 'skills', name: 'release-notes', writtenBy: 'laptop', keptAt: '2026-10-30T10:00:00Z', theirs: 'v2', mine: 'v3' };

describe('the wording of personal sync', () => {
  it('says each state in a word, and counts what this machine carries', () => {
    expect(syncStateWord('ready')).toEqual({ word: 'On', tone: 'good' });
    expect(syncStateWord('key-arrived').word).toBe('Key arrived');
    expect(syncStateWord('not-on-plan').word).toBe('Not on your plan');
    expect(kindCount({ kind: 'servers', items: 3 })).toBe('3 MCP servers');
    expect(kindCount({ kind: 'memory', items: 1 })).toBe('1 memory fact');
    expect(kindCount({ kind: 'other', items: 2 })).toBe('2 other');
  });

  it('splits a fingerprint into its six groups, written or not', () => {
    expect(fingerprintGroups('12345 67890 11121 31415 16171 81920')).toEqual(['12345', '67890', '11121', '31415', '16171', '81920']);
    expect(fingerprintGroups('123456789011121314151617181920')).toHaveLength(6);
  });

  it('says when it last ran, the conflicts, what was opened elsewhere and what waits on the key', () => {
    expect(lastSyncedLine(undefined)).toBe('Not synced on this machine yet.');
    expect(lastSyncedLine('5 min ago')).toBe('Last synced 5 min ago.');
    expect(conflictsLine(0)).toBe('No conflicts.');
    expect(conflictsLine(2)).toBe('2 conflicts to choose between.');
    expect(conflictCaption(conflict, '1 h ago')).toBe('Skill written on laptop, kept 1 h ago');
    expect(openedElsewhereLine(1)).toBe('1 repository opened on your other machines and not on this one.');
    expect(keyWaitsLine('Windows Hello', true)).toBe('Nothing moves yet. Giving the key waits for your signature with Windows Hello on the island.');
    expect(keyWaitsLine('Windows Hello', false)).toContain('Taking the key');
  });
});

describe('the personal sync use case', () => {
  it('reads the status, syncs now, and opens the conflicts beside this machine’s own', async () => {
    const daemon = new ScriptedDaemon({
      'personal-sync-status': (request) => [{ id: request.id, ok: true, personalSync: ready }],
      'personal-sync-now': (request) => [{ id: request.id, ok: true, personalSync: { ...ready, conflicts: 0 } }],
      'personal-sync-conflicts': (request) => [{ id: request.id, ok: true, personalSync: ready, syncConflicts: [conflict] }],
      'personal-sync-resolve': (request) => [{ id: request.id, ok: true, personalSync: { ...ready, conflicts: 0 } }],
    });
    const sync = new PersonalSync(daemon, new RequestIds());
    await sync.refresh();
    expect(sync.status).toEqual(ready);
    expect(await sync.syncNow()).toEqual({ kind: 'done' });
    expect(sync.status?.conflicts).toBe(0);
    await sync.loadConflicts();
    expect(sync.conflicts).toEqual([conflict]);
    expect(await sync.resolve('c_1', 'theirs')).toEqual({ kind: 'done' });
    expect(daemon.sent('personal-sync-resolve')[0]).toMatchObject({ syncConflictId: 'c_1', syncKeep: 'theirs' });
    expect(sync.conflicts).toEqual([]);
  });

  it('only proposes moving the key, sending the fingerprint the person compared', async () => {
    const daemon = new ScriptedDaemon({
      'personal-sync-key-offer': (request) => [{ id: request.id, ok: true, proposed: 'prp_offer', personalSync: ready }],
      'personal-sync-key-accept': (request) => [{ id: request.id, ok: false, error: 'That is not the fingerprint this machine shows, so the key stays where it is.' }],
    });
    const sync = new PersonalSync(daemon, new RequestIds());
    expect(await sync.offer('m_laptop', '12345 67890 11121 31415 16171 81920')).toEqual({ kind: 'proposed', id: 'prp_offer' });
    expect(daemon.sent('personal-sync-key-offer')[0]).toMatchObject({ syncMachineId: 'm_laptop', syncFingerprint: '12345 67890 11121 31415 16171 81920' });
    expect((await sync.accept('00000 00000 00000 00000 00000 00000')).kind).toBe('failed');
    const gone = new PersonalSync(new ScriptedDaemon(), new RequestIds());
    await gone.refresh();
    expect(gone.unreadable).toBe(true);
  });
});
