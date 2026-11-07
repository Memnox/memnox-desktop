import type { ProfileView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Profiles } from '../src/core/application/profiles';
import { RequestIds } from '../src/core/application/request-ids';
import { Agents } from '../src/core/application/studio';
import { applyWhereLine, choiceNames, packChangeLine, profileAppliedLine, profileContents, profileDraftFrom, profileFormOf, profileSavedLine } from '../src/core/domain/profile-lines';
import { ScriptedDaemon } from './doubles';

const backend: ProfileView = {
  id: 'backend-engineering',
  name: 'Backend Engineering',
  skills: ['review-checklist', 'release-notes'],
  mcpServers: ['postgres'],
  rulePack: { name: 'Careful', rules: 6 },
  updatedAt: '2026-10-30T10:00:00Z',
  missing: [],
};

const packs = [{ id: 'careful', name: 'Careful', toml: '[[policies]]' }];

describe('what a profile says', () => {
  it('counts what it bundles, never a score', () => {
    expect(profileContents(backend)).toBe('2 skills · 1 server · Careful, 6 rules');
    expect(profileContents({ skills: ['a'], mcpServers: [] })).toBe('1 skill · 0 servers · No rule pack');
  });

  it('says what an apply raised, what was already given and what was skipped', () => {
    expect(profileAppliedLine({ proposed: ['p1', 'p2'], already: ['postgres'], skipped: [] }, 'Windows Hello')).toBe('2 proposals wait for your signature with Windows Hello on the island. 1 was already given.');
    expect(profileAppliedLine({ proposed: [], already: [], skipped: ['figma is not in the MCP Hub.'] }, 'Windows Hello')).toBe('Skipped: figma is not in the MCP Hub.');
    expect(profileAppliedLine({ proposed: [], already: [], skipped: [] }, 'Windows Hello')).toBe('The profile holds nothing to give.');
  });

  it('says where skills go before Apply', () => {
    expect(applyWhereLine(' ')).toBe('Skills go into the agent’s home folder.');
    expect(applyWhereLine('/code/api')).toBe('Skills go into /code/api.');
  });
});

describe('the New profile dialog', () => {
  const form = { name: ' Backend ', description: '', skills: new Set(['b', 'a']), servers: new Set<string>(), pack: 'careful' };

  it('makes the draft with the pack’s text and sorted lists', () => {
    expect(profileDraftFrom(form, packs)).toEqual({ name: 'Backend', skills: ['a', 'b'], rulePack: { name: 'Careful', toml: '[[policies]]' } });
  });

  it('says what is missing', () => {
    expect(profileDraftFrom({ ...form, name: '' }, packs)).toBe('Give the profile a name.');
    expect(profileDraftFrom({ ...form, skills: new Set(), pack: '' }, packs)).toBe('Choose at least one skill, server or rule pack.');
    expect(profileDraftFrom({ ...form, pack: 'gone' }, packs)).toBe('That rule pack is no longer offered. Choose another.');
  });
});

describe('editing a profile', () => {
  const offered = [{ id: 'careful', name: 'Careful', ruleCount: 6 }];

  it('opens with the profile as kept and its pack matched by name', () => {
    expect(profileFormOf(backend, offered)).toEqual({ name: 'Backend Engineering', description: '', skills: new Set(['review-checklist', 'release-notes']), servers: new Set(['postgres']), pack: 'careful' });
    expect(profileFormOf(backend, []).pack).toBe('');
  });

  it('keeps a name the hub no longer holds tickable, after what it holds', () => {
    expect(choiceNames(['a', 'b'], new Set(['b', 'z', 'gone']))).toEqual(['a', 'b', 'gone', 'z']);
  });

  it('says what saving does to the pack the profile keeps', () => {
    const kept = { name: 'Careful', rules: 6 };
    expect(packChangeLine(undefined, { pack: '' }, offered)).toBeUndefined();
    expect(packChangeLine(kept, { pack: 'careful' }, offered)).toBeUndefined();
    expect(packChangeLine(kept, { pack: '' }, offered)).toBe('Saving takes Careful out of the profile.');
    expect(packChangeLine(kept, { pack: '' }, [])).toBe('Careful is no longer offered here, so saving takes it out of the profile. Choose a pack to keep one.');
    expect(packChangeLine(kept, { pack: 'open' }, [...offered, { id: 'open', name: 'Open', ruleCount: 2 }])).toBe('Saving replaces Careful with Open.');
    expect(packChangeLine(kept, { pack: 'careful' }, [{ id: 'careful', name: 'Careful', ruleCount: 7 }])).toBe('Saving takes Careful as it is offered now, 7 rules where the profile keeps 6.');
  });

  it('says a save grants nothing, new or edited', () => {
    expect(profileSavedLine('Backend', false)).toBe('Backend is kept. It gives nothing until you apply it.');
    expect(profileSavedLine('Backend', true)).toBe('Backend is saved. What it already gave stays, and the change gives nothing until you apply it again.');
  });
});

describe('profiles', () => {
  it('reads, keeps, applies and forgets, redrawing from every answer', async () => {
    const daemon = new ScriptedDaemon({
      profiles: (request) => [{ id: request.id, ok: true, profiles: [backend] }],
      'profile-put': (request) => [{ id: request.id, ok: true, profiles: [backend] }],
      'profile-apply': (request) => [{ id: request.id, ok: true, profiles: [backend], profileApplied: { profile: 'Backend Engineering', agent: 'claude-code', proposed: ['p1'], already: [], skipped: [] } }],
      'profile-remove': (request) => [{ id: request.id, ok: true, profiles: [] }],
    });
    const profiles = new Profiles(daemon, new RequestIds(), 'Windows Hello');
    await profiles.refresh();
    expect(profiles.profiles?.[0]?.name).toBe('Backend Engineering');
    expect(await profiles.put({ name: 'Backend Engineering' })).toEqual({ kind: 'done', note: 'Backend Engineering is kept. It gives nothing until you apply it.' });
    expect(await profiles.put({ name: 'Backend Engineering', skills: ['review-checklist'] }, true)).toEqual({ kind: 'done', note: 'Backend Engineering is saved. What it already gave stays, and the change gives nothing until you apply it again.' });
    expect(daemon.sent('profile-put')[1]?.profileDraft).toEqual({ name: 'Backend Engineering', skills: ['review-checklist'] });
    expect(await profiles.apply('backend-engineering', 'claude-code', ' /code/api ')).toEqual({ kind: 'done', note: '1 proposal waits for your signature with Windows Hello on the island.' });
    expect(daemon.sent('profile-apply')[0]).toMatchObject({ profileName: 'backend-engineering', profileAgent: 'claude-code', profileProject: '/code/api' });
    expect(await profiles.remove('backend-engineering')).toEqual({ kind: 'done', note: 'backend-engineering is forgotten. What it already gave stays where it was given.' });
    expect(profiles.profiles).toEqual([]);
  });

  it('leaves the project out for the home folder, and says a refusal', async () => {
    const daemon = new ScriptedDaemon({ 'profile-apply': (request) => [{ id: request.id, ok: false, error: 'No profile is called nope.' }] });
    const profiles = new Profiles(daemon, new RequestIds(), 'Windows Hello');
    expect(await profiles.apply('nope', 'codex-cli', '')).toEqual({ kind: 'failed', why: 'No profile is called nope.' });
    expect(daemon.sent('profile-apply')[0]?.profileProject).toBeUndefined();
  });

  it('launches with a profile and says both in one line', async () => {
    const daemon = new ScriptedDaemon({
      'agent-launch': (request) => [
        { id: request.id, ok: true, proposed: 'p1', agentLaunched: { agent: 'claude-code', workingDirectory: '/code/api', line: 'claude' }, profileApplied: { profile: 'Backend', agent: 'claude-code', proposed: ['p1', 'p2'], already: [], skipped: [] } },
      ],
    });
    const agents = new Agents(daemon, new RequestIds());
    const outcome = await agents.launch('claude-code', '/code/api', { name: 'Backend', keyTitle: 'Windows Hello' });
    expect(daemon.sent('agent-launch')[0]?.profileName).toBe('Backend');
    expect(outcome).toEqual({ kind: 'done', note: 'Opened claude-code in /code/api, typing claude. 2 proposals wait for your signature with Windows Hello on the island.' });
  });
});
