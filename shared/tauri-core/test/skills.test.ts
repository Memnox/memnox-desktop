import type { DaemonRequest, SkillView, SkillsHubView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { RequestIds } from '../src/core/application/request-ids';
import { SkillsHub } from '../src/core/application/skills';
import {
  assignedLine,
  assignedNote,
  assignmentChanges,
  categoryVersion,
  compatibilityLine,
  conversionLosses,
  draftFrom,
  heldLine,
  permissionLines,
  skillNameFrom,
  skillsSyncedLine,
  updatedLine,
} from '../src/core/domain/skills-lines';
import { ScriptedDaemon } from './doubles';

const skill: SkillView = {
  name: 'release-notes',
  scope: 'personal',
  category: 'Writing',
  version: '1.2.0',
  description: 'Drafts release notes from merged pull requests',
  enabled: true,
  digest: 'sha256:abc',
  agents: ['claude-code'],
  assignments: [{ agent: 'claude-code' }],
  compatibility: [
    { agent: 'claude-code', label: 'Claude Code', supported: true, loses: [] },
    { agent: 'cursor', label: 'Cursor', supported: true, loses: ['Its tool grant, since Cursor rules carry none'] },
  ],
  versions: [{ version: '1.2.0', current: true, acceptedAt: '2026-10-20T10:00:00Z' }],
  updatedAt: '2026-10-26T10:00:00Z',
  files: ['template.md'],
  instructions: 'Read the merged pull requests.',
  tools: ['Read'],
  mcpServers: ['github'],
  permissions: { filesystem: [], network: ['api.github.com'], commands: ['gh'] },
  dependencies: [],
};

const view: SkillsHubView = { skills: [skill], found: [], agents: [{ agent: 'claude-code', label: 'Claude Code', installed: true }] };

describe('what a skill card says', () => {
  it('counts the agents and the days, never a score', () => {
    expect(assignedLine(0)).toBe('No agents assigned');
    expect(assignedLine(1)).toBe('1 agent assigned');
    expect(assignedLine(3)).toBe('3 agents assigned');
    const now = Date.parse('2026-10-30T12:00:00Z');
    expect(updatedLine('2026-10-30T09:00:00Z', now)).toBe('Updated today');
    expect(updatedLine('2026-10-29T09:00:00Z', now)).toBe('Updated yesterday');
    expect(updatedLine('2026-10-26T10:00:00Z', now)).toBe('Updated 4 days ago');
    expect(categoryVersion(skill)).toBe('Writing · v1.2.0');
    expect(categoryVersion({ version: '2.0.0' })).toBe('v2.0.0');
  });

  it('says why a skill is held and whether accepting it is signed', () => {
    expect(heldLine({ standing: 'widened', gained: ['Bash', 'curl'], signed: true })).toBe(
      'Its folder reaches further than the version you accepted, so nothing new of it is handed out. It now reaches Bash and curl. Accepting it waits for your signature on the island.',
    );
    expect(heldLine({ standing: 'changed', gained: [], signed: false })).toContain('Accepting it happens at once.');
  });

  it('says what each agent keeps, and lists the losses for the agents chosen', () => {
    expect(compatibilityLine({ supported: true, loses: [] })).toBe('Keeps everything');
    expect(compatibilityLine({ supported: true, loses: ['a', 'b'] })).toBe('Loses 2 things in conversion');
    expect(compatibilityLine({ supported: false, loses: [] })).toBe('Cannot take skills');
    expect(conversionLosses(skill.compatibility, new Set(['cursor']))).toEqual([{ label: 'Cursor', loses: ['Its tool grant, since Cursor rules carry none'] }]);
    expect(conversionLosses(skill.compatibility, new Set(['claude-code']))).toEqual([]);
  });

  it('says a sync in a line', () => {
    expect(skillsSyncedLine({ written: 3, removed: 1, skipped: [{ skill: 'a', agent: 'b', path: 'p', reason: 'r' }] })).toBe('Wrote 3, removed 1, skipped 1.');
    expect(skillsSyncedLine({ written: 0, removed: 0, skipped: [] })).toBe('Every agent already has the skills the hub gives it.');
  });

  it('lists only the kinds of reach a skill asks for', () => {
    expect(permissionLines(skill).map((each) => each.title)).toEqual(['Agent tools', 'MCP servers', 'Commands', 'Hosts']);
  });
});

describe('the assign dialog', () => {
  it('sends only what changed', () => {
    expect(assignmentChanges(['claude-code', 'codex-cli'], new Set(['codex-cli', 'cursor']))).toEqual({ give: ['cursor'], take: ['claude-code'] });
  });

  it('says the gives wait on the island and the takes happened', () => {
    expect(assignedNote({ proposed: 2, done: 1, failed: [] }, 'Windows Hello')).toBe('2 agents wait for your signature with Windows Hello on the island. 1 change made at once.');
    expect(assignedNote({ proposed: 0, done: 0, failed: [] }, 'Windows Hello')).toBe('Nothing changed.');
    expect(assignedNote({ proposed: 1, done: 0, failed: ['no such agent'] }, 'Windows Hello')).toBe('no such agent');
  });
});

describe('the New skill form', () => {
  const form = { name: 'Release Notes!', version: '', description: 'Drafts notes', category: '', instructions: 'Do it.', tools: 'Read, Bash', commands: '' };

  it('names it as every agent folder takes, and fills the version', () => {
    expect(skillNameFrom('  Release Notes! ')).toBe('release-notes');
    expect(draftFrom(form)).toEqual({ name: 'release-notes', version: '1.0.0', description: 'Drafts notes', instructions: 'Do it.', tools: ['Read', 'Bash'] });
  });

  it('says what is missing', () => {
    expect(draftFrom({ ...form, name: '!!' })).toBe('Give the skill a name.');
    expect(draftFrom({ ...form, instructions: ' ' })).toBe('Write the instructions the agent follows.');
  });
});

describe('the Skills Hub', () => {
  it('reads the hub and redraws from every answer', async () => {
    const daemon = new ScriptedDaemon({ 'skills-hub': (request) => [{ id: request.id, ok: true, skillsHub: view }] });
    const hub = new SkillsHub(daemon, new RequestIds());
    await hub.refresh();
    expect(hub.hub?.skills[0]?.name).toBe('release-notes');
    expect(hub.unreadable).toBe(false);
  });

  it('gives with a signature and takes away at once, one request each', async () => {
    const daemon = new ScriptedDaemon({
      'skills-hub': (request) => [{ id: request.id, ok: true, skillsHub: view }],
      'skill-assign': (request: DaemonRequest) => [{ id: request.id, ok: true, ...(request.skillOn === true ? { proposed: `prp_${request.skillAgent ?? ''}` } : {}) }],
    });
    const hub = new SkillsHub(daemon, new RequestIds());
    await hub.refresh();
    const results = await hub.assignTo('release-notes', new Set(['cursor', 'codex-cli']));
    expect(results).toEqual({ proposed: 2, done: 1, failed: [] });
    expect(daemon.sent('skill-assign').map((request) => [request.skillAgent, request.skillOn])).toEqual([
      ['claude-code', false],
      ['codex-cli', true],
      ['cursor', true],
    ]);
  });

  it('says a sync with what it wrote, and a runtime that is gone', async () => {
    const daemon = new ScriptedDaemon({ 'skill-sync': (request) => [{ id: request.id, ok: true, skillsSynced: { written: 2, removed: 0, files: [], skipped: [] } }] });
    const hub = new SkillsHub(daemon, new RequestIds());
    expect(await hub.sync()).toEqual({ kind: 'done', note: 'Wrote 2.' });
    expect(await hub.accept('release-notes')).toEqual({ kind: 'failed', why: 'The runtime is not answering.' });
  });

  it('removes a personal skill from every agent at once', async () => {
    const daemon = new ScriptedDaemon({ 'skill-remove': (request) => [{ id: request.id, ok: true, skillsHub: { skills: [], found: [], agents: [] } }] });
    const hub = new SkillsHub(daemon, new RequestIds());
    expect(await hub.remove('release-notes')).toEqual({ kind: 'done', note: 'release-notes was taken out of the hub and every agent, its kept versions with it.' });
    expect(daemon.sent('skill-remove')[0]?.skillName).toBe('release-notes');
    expect(hub.hub?.skills).toEqual([]);
  });
});
