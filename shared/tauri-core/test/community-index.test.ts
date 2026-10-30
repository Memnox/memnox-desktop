import type { CommunityIndexView, IndexEntryView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { CommunityIndex } from '../src/core/application/community-index';
import { RequestIds } from '../src/core/application/request-ids';
import {
  canInstall,
  categoriesOf,
  inCategory,
  indexInstalledLine,
  indexKindWord,
  indexStateLine,
  installedLine,
  installWaitsLine,
  latestLine,
  publisherLine,
  supportedAgentsLine,
  yankedLine,
} from '../src/core/domain/index-lines';
import { ScriptedDaemon } from './doubles';

const skill: IndexEntryView = {
  id: 'lst_1',
  name: 'release-notes',
  kind: 'skill',
  description: 'Drafts release notes from merged pull requests',
  category: 'Writing',
  publisher: { kind: 'organization', name: 'Acme' },
  license: 'MIT',
  agents: ['claude-code', 'codex-cli'],
  latest: { version: '1.2.0', digest: 'sha256:abc' },
  yanked: ['1.1.0'],
  unsafe: false,
};

const pack: IndexEntryView = { id: 'lst_2', name: 'careful-pushes', kind: 'rule_pack', description: 'Asks before a push to main', category: 'Git', publisher: { kind: 'member', name: 'Sam' }, agents: [], yanked: ['1.0.0', '1.0.1'], unsafe: true };

const index: CommunityIndexView = { source: 'https://memnox.com/index.json', fetchedAt: '2026-10-30T11:55:00Z', complete: true, entries: [skill, pack] };

describe('what a listing says', () => {
  it('names the kind, the publisher and the agents', () => {
    expect(indexKindWord('rule_pack')).toBe('Rule pack');
    expect(indexKindWord('skill')).toBe('Skill');
    expect(publisherLine(skill.publisher)).toBe('By Acme');
    expect(supportedAgentsLine(skill.agents)).toBe('For Claude Code and Codex');
    expect(supportedAgentsLine([])).toBe('Works with every agent');
  });

  it('offers the latest safe version and never one marked unsafe', () => {
    expect(latestLine(skill)).toBe('v1.2.0');
    expect(canInstall(skill)).toBe(true);
    expect(latestLine(pack)).toBe('No safe version to install');
    expect(canInstall(pack)).toBe(false);
    expect(yankedLine(pack.yanked)).toBe('2 versions marked unsafe');
    expect(yankedLine(skill.yanked)).toBe('1 version marked unsafe');
    expect(yankedLine([])).toBeUndefined();
  });

  it('says what is already in My Skills and where an install waits', () => {
    expect(installedLine({ ...skill, installed: '1.0.0' })).toBe('v1.0.0 in My Skills');
    expect(installedLine(skill)).toBeUndefined();
    expect(installWaitsLine('skill', 'Windows Hello')).toBe('Installing a skill puts it in My Skills, where it waits for you to accept it before any agent is given it.');
    expect(installWaitsLine('rule_pack', 'Windows Hello')).toBe('Installing a rule pack proposes each of its rules, and each waits for your signature with Windows Hello on the island.');
  });

  it('filters by category on the window', () => {
    expect(categoriesOf([skill, pack, { ...skill, id: 'x' }])).toEqual(['Git', 'Writing']);
    expect(inCategory([skill, pack], 'Git').map((entry) => entry.name)).toEqual(['careful-pushes']);
    expect(inCategory([skill, pack], undefined)).toHaveLength(2);
  });

  it('says where the index came from, or why it is not fresh', () => {
    const now = Date.parse('2026-10-30T12:00:00Z');
    expect(indexStateLine(index, now)).toBe('Read from https://memnox.com/index.json 5 minutes ago.');
    expect(indexStateLine({ ...index, said: 'Offline, so this is what was read yesterday.' }, now)).toBe('Offline, so this is what was read yesterday.');
    expect(indexStateLine({ source: 'git', complete: false }, now)).toBe('Not read from git yet. It held more than it carries, so some listings are not shown.');
  });

  it('says an install in a line', () => {
    expect(indexInstalledLine({ name: 'release-notes', kind: 'skill', version: '1.2.0', proposed: [], held: true }, 'Windows Hello')).toBe('release-notes v1.2.0 is in My Skills, waiting for you to accept it.');
    expect(indexInstalledLine({ name: 'careful', kind: 'rule_pack', version: '2.0.0', proposed: ['p1', 'p2', 'p3'], held: false }, 'Windows Hello')).toBe('3 rules wait from careful v2.0.0 for your signature with Windows Hello on the island.');
  });
});

describe('the community index', () => {
  it('asks with the words and kind and keeps what came back', async () => {
    const daemon = new ScriptedDaemon({ 'index-list': (request) => [{ id: request.id, ok: true, communityIndex: index }] });
    const community = new CommunityIndex(daemon, new RequestIds(), 'Windows Hello');
    await community.refresh({ query: ' notes ', kind: 'skill' }, true);
    expect(daemon.sent('index-list')[0]).toMatchObject({ indexQuery: 'notes', indexKind: 'skill', indexRefresh: true });
    expect(community.index?.entries).toHaveLength(2);
    expect(community.filter.kind).toBe('skill');
    await community.readPacks();
    expect(daemon.sent('index-list')[1]?.indexKind).toBe('rule_pack');
  });

  it('says an install, and a runtime that refused it', async () => {
    const daemon = new ScriptedDaemon({
      'index-install': (request) =>
        request.indexName === 'careful-pushes'
          ? [{ id: request.id, ok: false, error: 'Every version of careful-pushes is marked unsafe.' }]
          : [{ id: request.id, ok: true, indexInstalled: { id: 'lst_1', name: 'release-notes', kind: 'skill', version: '1.2.0', digest: 'sha256:abc', proposed: [], held: true, said: '' } }],
    });
    const community = new CommunityIndex(daemon, new RequestIds(), 'Windows Hello');
    expect(await community.install('release-notes', '1.2.0')).toEqual({ kind: 'done', note: 'release-notes v1.2.0 is in My Skills, waiting for you to accept it.' });
    expect(daemon.sent('index-install')[0]).toMatchObject({ indexName: 'release-notes', indexVersion: '1.2.0' });
    expect(await community.install('careful-pushes')).toEqual({ kind: 'failed', why: 'Every version of careful-pushes is marked unsafe.' });
  });
});
