import type { MemoryItemView, ProjectView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { projectRoute, PROJECTS_ROUTE } from '../src/core/domain/destinations';
import {
  BACK_TO_PROJECTS,
  canUse,
  moreLine,
  projectPageInfo,
  TEAM_TOOLS_SHOWN,
  cloudProjectLink,
  editableHere,
  linkedToolCount,
  projectAgents,
  projectCrumbs,
  projectDescription,
  projectMemory,
  projectSidebar,
  projectToolCards,
  readyLine,
  readySteps,
  renamedDraft,
  renameProblem,
  showReady,
  showsTeam,
  shownToolCards,
  teamLine,
  toolCategory,
  toolCategoryCounts,
  toolsToAdd,
} from '../src/core/domain/project-sidebar';

const project = (extra: Partial<ProjectView> = {}): ProjectView => ({
  id: 'p1',
  name: 'Spring launch',
  path: '/work/launch',
  declared: true,
  opened: true,
  agents: ['claude-code'],
  agentsSeen: ['claude-code'],
  sessions: { total: 3, ended: 2 },
  servers: [],
  skills: [],
  rules: { count: 0, inForce: false },
  instructions: [],
  memoryScope: 'project',
  openMissions: [],
  openQuestions: 0,
  ...extra,
});

const organization = { id: 'org proj', name: 'Acme', repository: 'github.com/acme/launch', description: 'The spring campaign', servers: ['slack'], skills: [], rules: 0, memory: 'project', skipped: [], editedIn: 'Changed in Memnox Cloud' };

describe('the sidebar a project swaps in', () => {
  it('leads with the way back and the project’s name, then its four pages, the one shown lit', () => {
    const sidebar = projectSidebar(project(), projectRoute('p1', 'agents'));
    expect(sidebar.back).toEqual({ title: BACK_TO_PROJECTS, route: PROJECTS_ROUTE });
    expect(BACK_TO_PROJECTS).toBe('Back to Projects');
    expect(sidebar.name).toBe('Spring launch');
    expect(sidebar.rows.map((row) => row.title)).toEqual(['Overview', 'Agents', 'Memory', 'What its AI may do']);
    expect(sidebar.rows.filter((row) => row.chosen).map((row) => row.page)).toEqual(['agents']);
    expect(sidebar.rows[1]?.route).toEqual(projectRoute('p1', 'agents'));
    expect(projectRoute('p1', 'tools')).toEqual(projectRoute('p1'));
    expect(projectCrumbs(project(), 'autonomy')).toEqual(['Projects', 'Spring launch', 'What its AI may do']);
  });

  it('lays the tools out as a catalogue, the repository one shelf among many and listed after the rest', () => {
    const cards = projectToolCards(
      project({
        servers: [
          { name: 'linear', inHub: true, agents: ['claude-code'] },
          { name: 'search', inHub: false, agents: [] },
        ],
        instructions: [{ path: 'BRIEF.md', source: true, present: true, agents: ['claude-code'], written: false }],
      }),
      { hub: ['linear', 'postgres'], connections: [{ toolkit: 'slack', connected: true }, { toolkit: 'notion', connected: false }] },
    );
    expect(cards.map((card) => `${card.category} ${card.name} ${card.linked}`)).toEqual([
      'tickets linear true',
      'servers search true',
      'files BRIEF.md true',
      'channels Slack true',
      'repositories /work/launch true',
      'servers postgres false',
    ]);
    expect(cards.find((card) => card.name === 'search')?.ready).toBe(false);
    expect(cards.find((card) => card.name === 'postgres')?.action).toEqual({ kind: 'add-server', server: 'postgres' });
    expect(toolCategoryCounts(cards).map((each) => `${each.title} ${each.count}`)).toEqual(['Files 1', 'Channels 1', 'Tickets 1', 'Repositories 1', 'Servers 2']);
    expect(shownToolCards(cards, 'servers', '').map((card) => card.name)).toEqual(['search', 'postgres']);
    expect(shownToolCards(cards, 'all', 'slack').map((card) => card.name)).toEqual(['Slack']);
    expect(linkedToolCount(cards)).toBe(4);
    expect(toolCategory('zoom', 'apps')).toBe('meetings');
    expect(toolsToAdd(project({ servers: [{ name: 'linear', inHub: true, agents: [] }] }), ['linear', 'slack'])).toEqual(['slack']);
  });

  it('offers documents and an app on an empty project, leaving the team shelves for later, and no add on one it cannot change', () => {
    expect(TEAM_TOOLS_SHOWN).toBe(false);
    const empty = projectToolCards(project({ path: '' }));
    expect(empty.map((card) => card.name)).toEqual(['Add documents', 'Add an app']);
    expect(empty.find((card) => card.name === 'Add an app')?.action).toEqual({ kind: 'connect' });
    expect(projectPageInfo('tools').summary).toBe('Where this project’s work happens, and what its agents learn from.');
    expect(projectPageInfo('overview').summary).toBe('What this project is, what it still needs, and what it learned lately.');
    const shared = projectToolCards(project({ scope: 'organization', organization }), { hub: ['postgres'], connections: [] });
    expect(shared.some((card) => card.action?.kind === 'add-server')).toBe(false);
  });

  it('shows an organization’s project read only, with its own page in Memnox Cloud', () => {
    const shared = project({ scope: 'organization', organization });
    expect(editableHere(shared)).toBe(false);
    expect(editableHere(project())).toBe(true);
    expect(cloudProjectLink(shared)).toBe('https://app.memnox.com/projects/org%20proj');
    expect(cloudProjectLink(project())).toBe('https://app.memnox.com/projects');
    expect(projectDescription(shared)).toBe('The spring campaign');
    expect(projectToolCards(shared).filter((card) => card.linked).map((card) => card.name)).toEqual(['slack', 'github.com/acme/launch']);
  });

  it('describes a project by what it is busy with when nobody wrote a description', () => {
    expect(projectDescription(project({ openMissions: [{ id: 'm', statement: 'the press kit', startedAt: '2026-11-01T00:00:00Z' }] }))).toBe('Working on the press kit');
    expect(projectDescription(project())).toBeUndefined();
  });
});

describe('Get it ready', () => {
  it('asks for what its AI may do, a page of the project, with adding tools left off', () => {
    const steps = readySteps({ tools: 0, rules: 0 });
    expect(steps.map((step) => `${step.title} ${step.page} ${step.done}`)).toEqual(['Choose what its AI may do autonomy false']);
    expect(readyLine({ tools: 2, rules: 0 })).toBe('0 of 1 done');
  });

  it('shows while the project has no rules of its own, and goes once it has one', () => {
    expect(showReady({ tools: 0, rules: 0 })).toBe(true);
    expect(showReady({ tools: 1, rules: 0 })).toBe(true);
    expect(showReady({ tools: 0, rules: 1 })).toBe(false);
  });
});

describe('what a project learned', () => {
  it('keeps its own facts, by folder or by name, the newest first', () => {
    const item = (id: string, project: string | undefined, createdAt: string, scope: MemoryItemView['scope'] = 'project') => ({ id, scope, createdAt, ...(project === undefined ? {} : { project }) });
    const items = [item('a', '/work/launch/', '2026-11-01'), item('b', 'Spring launch', '2026-11-03'), item('c', '/work/other', '2026-11-04'), item('d', undefined, '2026-11-05', 'personal')];
    expect(projectMemory(items, project()).map((each) => each.id)).toEqual(['b', 'a']);
  });
});

describe('Agents', () => {
  it('lists the agents the project names with what each is given, then those only seen here', () => {
    const shared = project({
      agents: ['claude-code', 'codex-cli'],
      agentsSeen: ['claude-code', 'cursor'],
      skills: [{ name: 'review', inHub: true, agents: ['claude-code'] }],
      servers: [{ name: 'linear', inHub: true, agents: ['claude-code'] }, { name: 'slack', inHub: true, agents: ['claude-code'] }],
    });
    const { given, seenOnly } = projectAgents(shared, { 'claude-code': 'Claude Code' });
    expect(given.map((agent) => `${agent.name}: ${agent.line} ${agent.seen}`)).toEqual(['Claude Code: 1 skill, 2 servers true', expect.stringMatching(/: 0 skills, 0 servers false$/)]);
    expect(seenOnly.map((agent) => agent.kind)).toEqual(['cursor']);
    expect(seenOnly[0]?.line).toBe('Ran a session here, and the project gives it nothing');
  });
});

describe('Your team', () => {
  it('shows only once this computer is signed in or the organization shares the project', () => {
    const shared = project({ scope: 'organization', organization });
    expect(showsTeam(project(), false)).toBe(false);
    expect(showsTeam(project(), true)).toBe(true);
    expect(showsTeam(shared, false)).toBe(true);
    expect(teamLine(shared)).toBe('Your organization shares this project as Acme, so the people on it and their agents work under the same rules. Who is on it is changed in Memnox Cloud.');
    expect(teamLine(project())).toBe('Only you work in this project. Share it in Memnox Cloud and your team’s agents work in it under the same rules as yours.');
  });
});

describe('What its AI can use', () => {
  it('names its agents, skills and apps, with no people or team while this computer is alone', () => {
    const own = project({ skills: [{ name: 'review', inHub: true, agents: [] }], servers: [{ name: 'linear', inHub: true, agents: [] }] });
    const alone = canUse(own, false, { 'claude-code': 'Claude Code' });
    expect(alone.map((part) => `${part.title} ${part.names.join(',')}`)).toEqual(['AI agents Claude Code', 'Skills review', 'Apps linear']);
    expect(alone.map((part) => part.target)).toEqual([
      { kind: 'page', page: 'agents' },
      { kind: 'shared', row: 'skills' },
      { kind: 'shared', row: 'connectors' },
    ]);
    expect(alone.some((part) => /people|team/.test(`${part.empty} ${part.what}`))).toBe(false);
    expect(canUse(project({ agents: [] }), false)[0]?.empty).toBe('Any AI agent you use');
    const joined = canUse(project({ agents: [], scope: 'organization', organization }), false);
    expect(joined[0]?.empty).toBe('Any AI agent its people use');
    expect(joined[1]?.what).toContain('your team');
    expect(joined[2]?.names).toEqual(['slack']);
    expect(moreLine({ names: ['a', 'b', 'c', 'd', 'e'] })).toBe('and 2 more');
    expect(moreLine({ names: ['a'] })).toBeUndefined();
  });
});

describe('renaming a project', () => {
  it('writes its manifest under the new name, and refuses an empty name or an organization’s project', () => {
    expect(renamedDraft(project(), '  Autumn launch ')).toMatchObject({ name: 'Autumn launch' });
    expect(renameProblem(' ', project())).toBe('Give it a name.');
    expect(renameProblem('Spring launch', project())).toBe('That is already its name.');
    expect(renameProblem('New', project())).toBeUndefined();
    expect(renameProblem('New', project({ scope: 'organization', organization }))).toContain('Memnox Cloud');
  });
});
