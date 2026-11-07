import type { CommunityIndexView, IndexEntryView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { CommunityIndex } from '../src/core/application/community-index';
import { RequestIds } from '../src/core/application/request-ids';
import {
  canInstall,
  categoriesOf,
  inCategory,
  INDEX_ADDRESS_WANTED,
  indexInstalledLine,
  indexKindWord,
  indexSourceLine,
  indexSourceProposedLine,
  indexStateLine,
  isIndexAddress,
  needsGroups,
  needsSummaryLine,
  installedLine,
  installWaitsLine,
  latestLine,
  publisherLine,
  supportedAgentsLine,
  warningsCountLine,
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
  needs: { filesystem: ['./CHANGELOG.md'], network: [], commands: ['git log', 'gh pr list'], mcpServers: ['github'], tools: [] },
  warnings: [],
};

const pack: IndexEntryView = { id: 'lst_2', name: 'careful-pushes', kind: 'rule_pack', description: 'Asks before a push to main', category: 'Git', publisher: { kind: 'member', name: 'Sam' }, agents: [], yanked: ['1.0.0', '1.0.1'], unsafe: true, warnings: ['It runs any command its rules allow.'] };

const index: CommunityIndexView = { source: 'https://memnox.com/index.json', marketplace: true, fetchedAt: '2026-10-30T11:55:00Z', complete: true, entries: [skill, pack] };

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

  it('says what a listing needs in a line, and each kind of need on open', () => {
    expect(needsSummaryLine(skill.needs)).toBe('Needs 1 path, 2 commands and 1 MCP server');
    expect(needsSummaryLine(pack.needs)).toBe('Says nothing about what it needs, since the index carries no manifest for it');
    expect(needsSummaryLine({ filesystem: [], network: [], commands: [], mcpServers: [], tools: [] })).toBe('Needs no files, network, commands, MCP servers or tools');
    expect(needsGroups(skill.needs).map((group) => [group.title, group.items])).toEqual([
      ['Files', ['./CHANGELOG.md']],
      ['Commands', ['git log', 'gh pr list']],
      ['MCP servers', ['github']],
    ]);
    expect(needsGroups(undefined)).toEqual([]);
  });

  it('counts what to know before installing, and says nothing when nothing stands out', () => {
    expect(warningsCountLine(pack.warnings)).toBe('1 thing to know before installing');
    expect(warningsCountLine(['a', 'b'])).toBe('2 things to know before installing');
    expect(warningsCountLine([])).toBeUndefined();
  });

  it('says where listings come from, and offers only an https index', () => {
    expect(indexSourceLine(index)).toBe('Listings come from the Memnox marketplace, at https://memnox.com/index.json.');
    expect(indexSourceLine({ source: 'https://example.com/index.json', marketplace: false })).toBe('Listings come from https://example.com/index.json, an index you named rather than the Memnox marketplace.');
    expect(isIndexAddress(' https://example.com/index.json ')).toBe(true);
    expect(isIndexAddress('http://example.com/index.json')).toBe(false);
    expect(isIndexAddress('index.json')).toBe(false);
    expect(INDEX_ADDRESS_WANTED).toBe('Give an https address to an index.json.');
    expect(indexSourceProposedLine('Windows Hello')).toBe('Waiting on the island: sign it with Windows Hello and listings come from there.');
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

  it('proposes another index, resets to the marketplace at once, and never sends the source on a list', async () => {
    const daemon = new ScriptedDaemon({
      'index-source-set': (request) =>
        request.indexSource === 'marketplace' ? [{ id: request.id, ok: true, communityIndex: index }] : [{ id: request.id, ok: true, proposed: 'prp_1', communityIndex: index }],
      'index-list': (request) => [{ id: request.id, ok: true, communityIndex: index }],
    });
    const community = new CommunityIndex(daemon, new RequestIds(), 'Windows Hello');
    expect(await community.setSource(' https://example.com/index.json ')).toEqual({ kind: 'proposed', note: 'Waiting on the island: sign it with Windows Hello and listings come from there.' });
    expect(daemon.sent('index-source-set')[0]?.indexSource).toBe('https://example.com/index.json');
    expect(community.index?.marketplace).toBe(true);
    expect(await community.setSource()).toEqual({ kind: 'done', note: 'Listings come from the Memnox marketplace again.' });
    expect(daemon.sent('index-source-set')[1]?.indexSource).toBe('marketplace');
    await community.refresh();
    expect(daemon.sent('index-list')[0]?.indexSource).toBeUndefined();
  });

  it('says a source the runtime refused', async () => {
    const daemon = new ScriptedDaemon({ 'index-source-set': (request) => [{ id: request.id, ok: false, error: 'Only this machine names where the index comes from.' }] });
    const community = new CommunityIndex(daemon, new RequestIds(), 'Windows Hello');
    expect(await community.setSource('https://example.com/index.json')).toEqual({ kind: 'failed', why: 'Only this machine names where the index comes from.' });
  });
});
