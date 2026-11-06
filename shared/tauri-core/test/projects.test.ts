import type { PolicyRuleView, ProjectView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Projects } from '../src/core/application/projects';
import { RequestIds } from '../src/core/application/request-ids';
import {
  appliedLine,
  draftOf,
  everywhereLine,
  foldersToOpen,
  grantLine,
  instructionWord,
  organizationMemoryLine,
  organizationRulesLine,
  projectRules,
  projectStanding,
  projectTiles,
  questionsLine,
  readersLine,
  rulesLine,
  sessionsLine,
  sharedBy,
} from '../src/core/domain/project-lines';
import { ScriptedDaemon } from './doubles';

const project: ProjectView = {
  id: 'prj_1',
  name: 'memnox-desktop',
  path: '/code/memnox-desktop',
  declared: true,
  opened: true,
  agents: ['claude-code', 'codex-cli'],
  agentsSeen: ['claude-code'],
  sessions: { total: 4, ended: 3 },
  servers: [{ name: 'github', inHub: true, agents: ['claude-code'] }],
  skills: [
    { name: 'review-checklist', inHub: true, agents: ['claude-code', 'codex-cli'] },
    { name: 'gone', inHub: false, agents: [] },
  ],
  rules: { file: 'memnox.policies.toml', count: 3, inForce: true },
  instructions: [{ path: 'CLAUDE.md', source: true, present: true, agents: ['claude-code'], written: false }],
  memoryScope: 'project',
  openMissions: [{ id: 'm1', statement: 'Ship the projects view', startedAt: '2026-10-29T10:00:00Z' }],
  openQuestions: 2,
};

const rule = (name: string, extra: Partial<PolicyRuleView> = {}): PolicyRuleView => ({ name, effect: 'ask', match: { actions: ['git.push'] }, sentence: name, source: 'file', editable: false, ...extra });

describe('the wording of a project', () => {
  it('counts agents, skills, servers and the rules in force, never a score', () => {
    expect(projectTiles(project)).toEqual([
      { value: 2, label: 'Agents' },
      { value: 2, label: 'Skills' },
      { value: 1, label: 'MCP server' },
      { value: 3, label: 'Active rules' },
    ]);
    expect(projectTiles({ ...project, rules: { ...project.rules, inForce: false } })[3]).toEqual({ value: 0, label: 'Active rules' });
  });

  it('says a manifest that will not read before anything else', () => {
    expect(projectStanding({ ...project, problems: ['bad toml'] })).toEqual({ word: 'Manifest will not read', tone: 'bad' });
    expect(projectStanding({ ...project, declared: false })).toEqual({ word: 'Found, not saved', tone: 'quiet' });
    expect(projectStanding({ ...project, opened: false }).word).toBe('Not opened here');
    expect(projectStanding(project).word).toBe('Opened');
  });

  it('names the agents that read an instruction file', () => {
    expect(readersLine({ agents: ['claude-code', 'codex-cli'] })).toBe('Claude Code and Codex read it');
    expect(readersLine({ agents: ['cursor'] })).toBe('Cursor reads it');
    expect(readersLine({ agents: [] })).toBe('No agent here reads it');
    expect(instructionWord({ source: true, present: true, written: true })).toBe('Source, written by Memnox');
    expect(instructionWord({ source: false, present: false, written: false })).toBe('Missing');
  });

  it('says a grant the hub lacks reaches nobody', () => {
    expect(grantLine({ inHub: true, agents: ['claude-code'] }, 2)).toBe('Given to 1 of 2 agents');
    expect(grantLine({ inHub: false, agents: [] }, 2)).toBe('Not in the hub on this computer, so no agent is given it');
  });

  it('says why no rule of the project is in force', () => {
    expect(rulesLine(project.rules)).toBe('3 rules from memnox.policies.toml, in force.');
    expect(rulesLine({ count: 0, inForce: false })).toBe('This project names no rule file, so the rules of this computer hold.');
    expect(rulesLine({ file: 'p.toml', count: 1, inForce: false })).toBe('1 rule in p.toml, not in force until applying is signed.');
    expect(rulesLine({ file: 'p.toml', count: 0, inForce: false, problem: 'no such file' })).toBe('p.toml will not load: no such file');
    expect(questionsLine(0)).toBe('No open questions');
    expect(questionsLine(1)).toBe('1 open question');
    expect(sessionsLine({ sessions: { total: 1, ended: 0 } }, 0)).toBe('1 session, 0 ended. Never applied.');
    expect(sessionsLine({ sessions: { total: 3, ended: 2 } }, 0)).toBe('3 sessions, 2 ended. Never applied.');
  });

  it('says what applying did at once and what the hub lacks', () => {
    expect(appliedLine({ written: ['AGENTS.md', 'CLAUDE.md'], removed: [], kept: ['.cursorrules'], governed: [], missing: ['linear'] })).toBe(
      'Wrote 2 instruction files, left 1 of yours alone. The hub here lacks linear, so no agent is given it.',
    );
    expect(appliedLine({ written: [], removed: [], kept: [], governed: [], missing: [] })).toBe('Every agent already had this project’s instructions.');
  });

  it('keeps to the rules that reach into the project, counting the ones that hold everywhere apart', () => {
    const rules = [
      rule('from-file', { file: '/code/memnox-desktop/memnox.policies.toml' }),
      rule('in-folder', { match: { actions: ['git.push'], workingDirectories: ['/code/memnox-desktop/**'] } }),
      rule('elsewhere', { match: { actions: ['git.push'], workingDirectories: ['/code/other'] } }),
      rule('everywhere'),
    ];
    const { here, everywhere } = projectRules(rules, project);
    expect(here.map((each) => each.name)).toEqual(['from-file', 'in-folder']);
    expect(everywhere).toBe(1);
  });

  it('makes a found project into the manifest it shows now', () => {
    expect(draftOf(project)).toEqual({
      name: 'memnox-desktop',
      agents: ['claude-code', 'codex-cli'],
      servers: ['github'],
      skills: ['review-checklist', 'gone'],
      instructions: ['CLAUDE.md'],
      policy: 'memnox.policies.toml',
      memory: 'project',
    });
    expect(draftOf({ ...project, agents: [], servers: [], skills: [], instructions: [], rules: { count: 0, inForce: false }, memoryScope: '' })).toEqual({ name: 'memnox-desktop' });
  });

  it('offers only the session folders that are not projects yet', () => {
    expect(foldersToOpen([{ path: '/code/memnox-desktop/', name: 'memnox-desktop' }, { path: '/code/other', name: 'other' }], [project])).toEqual([{ path: '/code/other', name: 'other' }]);
  });
});

describe('the projects use case', () => {
  const view = { projects: [project] };

  it('reads the projects and says when the runtime does not answer', async () => {
    const projects = new Projects(new ScriptedDaemon({ projects: (request) => [{ id: request.id, ok: true, projects: view }] }), new RequestIds());
    await projects.refresh();
    expect(projects.projects).toEqual([project]);
    const down = new Projects(new ScriptedDaemon(), new RequestIds());
    await down.refresh();
    expect(down.unreadable).toBe(true);
  });

  it('opens a folder, saying what went at once and that the rest waits on the island', async () => {
    const daemon = new ScriptedDaemon({
      'project-open': (request) => [{ id: request.id, ok: true, projects: view, proposed: 'prp_1', projectApplied: { written: ['CLAUDE.md'], removed: [], kept: [], governed: [], missing: [] } }],
    });
    const projects = new Projects(daemon, new RequestIds());
    expect(await projects.open(' /code/memnox-desktop ')).toEqual({ kind: 'proposed', id: 'prp_1', note: 'Wrote 1 instruction file.' });
    expect(daemon.sent('project-open')[0]).toMatchObject({ projectPath: '/code/memnox-desktop' });
    expect(projects.projects).toEqual([project]);
  });

  it('saves a found project and applies one by id, passing a refusal on in the runtime’s words', async () => {
    const daemon = new ScriptedDaemon({
      'project-put': (request) => [{ id: request.id, ok: true, projects: view }],
      'project-apply': (request) => [{ id: request.id, ok: false, error: 'No project prj_9.' }],
    });
    const projects = new Projects(daemon, new RequestIds());
    expect((await projects.put(project.path, { name: 'memnox-desktop' })).kind).toBe('done');
    expect(daemon.sent('project-put')[0]).toMatchObject({ projectPath: '/code/memnox-desktop', projectDraft: { name: 'memnox-desktop' } });
    expect(await projects.apply('prj_9')).toEqual({ kind: 'failed', why: 'No project prj_9.' });
  });
});

describe('a project the organization shares', () => {
  const organization = { id: 'op_1', name: 'API', repository: 'github.com/acme/api', servers: ['github'], skills: [], rulePack: 'Release rules', rules: 4, memory: 'project', skipped: [], editedIn: 'API is the organization’s project, so it is changed in Memnox Cloud rather than here.' };

  it('is read only only when the organization names it', () => {
    expect(sharedBy({ scope: 'organization', organization })).toBe(organization);
    expect(sharedBy({ organization })).toBeUndefined();
    expect(sharedBy({})).toBeUndefined();
  });

  it('says its rule pack with a count and where its memory is kept', () => {
    expect(organizationRulesLine(organization)).toBe('Release rules, 4 rules');
    expect(organizationRulesLine({ rules: 0 })).toBe('No rule pack from the organization.');
    expect(organizationMemoryLine('none')).toBe('Its agents keep no memory from this project.');
    expect(organizationMemoryLine('project')).toBe('What its agents learn is kept under the organization’s project rather than this folder.');
  });
});

describe('the rules every project shares', () => {
  it('says how many hold here too in the Mac’s words, pinned in ProjectLinesTests.swift as well', () => {
    expect(everywhereLine(1)).toBe('1 rule of this computer holds here too, as in every project.');
    expect(everywhereLine(3)).toBe('3 rules of this computer hold here too, as in every project.');
  });
});
