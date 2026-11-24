import type { ProfileView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Profiles } from '../src/core/application/profiles';
import { RequestIds } from '../src/core/application/request-ids';
import { Agents } from '../src/core/application/studio';
import { profileAppliedLine, profileContents, profileSavedLine } from '../src/core/domain/profile-lines';
import { NO_LEVELS } from '../src/core/domain/agent-wire';
import { ScriptedDaemon } from './doubles';

const backend: ProfileView = {
  id: 'backend-engineering',
  name: 'Backend Engineering',
  skills: ['review-checklist', 'release-notes'],
  mcpServers: ['postgres'],
  rulePack: { name: 'Careful', rules: 6 },
  updatedAt: '2026-10-30T10:00:00Z',
  missing: [],
  projects: [],
  connections: [],
  levels: NO_LEVELS,
};

describe('what a profile says', () => {
  it('counts what it bundles, never a score', () => {
    expect(profileContents(backend)).toBe('2 skills · 1 server · Careful, 6 rules');
    expect(profileContents({ skills: ['a'], mcpServers: [] })).toBe('1 skill · 0 servers · No starter rules');
  });

  it('says what an apply raised, what was already given and what was skipped', () => {
    expect(profileAppliedLine({ proposed: ['p1', 'p2'], already: ['postgres'], skipped: [] }, 'Windows Hello')).toBe('2 changes wait for your OK with Windows Hello on the island. 1 was already given.');
    expect(profileAppliedLine({ proposed: [], already: [], skipped: ['figma is not in the MCP Hub.'] }, 'Windows Hello')).toBe('Skipped: figma is not in the MCP Hub.');
    expect(profileAppliedLine({ proposed: [], already: [], skipped: [] }, 'Windows Hello')).toBe('The profile holds nothing to give.');
  });
});

describe('saving a profile', () => {
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
    expect(await profiles.apply('backend-engineering', 'claude-code', ' /code/api ')).toEqual({ kind: 'done', note: '1 change waits for your OK with Windows Hello on the island.' });
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
    expect(outcome).toEqual({ kind: 'done', note: 'Opened claude-code in /code/api, typing claude. 2 changes wait for your OK with Windows Hello on the island.' });
  });
});

describe('profiles, as the agents list steers them', () => {
  const kept: ProfileView = { ...backend, id: 'backend', name: 'Backend', skills: [], mcpServers: [], rulePack: undefined };

  it('binds and unbinds an agent unsigned', async () => {
    const daemon = new ScriptedDaemon({
      'profile-bind': (request) => [{ id: request.id, ok: true, profiles: [kept] }],
      'profile-unbind': (request) => [{ id: request.id, ok: true, profiles: [] }],
    });
    const profiles = new Profiles(daemon, new RequestIds(), 'Windows Hello');
    expect(await profiles.bind('Backend', 'agt_claude-code')).toEqual({ kind: 'done', note: 'The agent now works under Backend.' });
    expect(daemon.sent('profile-bind')[0]?.signature).toBeUndefined();
    expect(await profiles.unbind('agt_codex-cli', 'backend')).toEqual({ kind: 'done', note: 'The agent is back on its own default.' });
    expect(daemon.sent('profile-unbind')[0]?.agentId).toBe('agt_codex-cli');
    expect(profiles.profiles).toEqual([]);
  });

  it('fills in what a runtime from before roles leaves out, raising no level', async () => {
    const old = { id: 'docs', name: 'Docs', skills: ['a'], mcpServers: [], updatedAt: '', missing: [] };
    const daemon = new ScriptedDaemon({ profiles: (request) => [{ id: request.id, ok: true, profiles: [old as unknown as ProfileView] }] });
    const profiles = new Profiles(daemon, new RequestIds(), 'Windows Hello');
    await profiles.refresh();
    expect(profiles.profiles?.[0]).toMatchObject({ connections: [], projects: [], levels: NO_LEVELS });
  });
});
