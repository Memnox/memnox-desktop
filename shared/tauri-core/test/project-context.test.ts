import type { MemoryItemView, ProjectView, SessionCard } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { projectRoute, type Supports } from '../src/core/domain/destinations';
import {
  choiceKey,
  choiceOfKey,
  inLine,
  matching,
  memoryChoices,
  memoryOwner,
  memoryReach,
  projectMemorySplit,
  projectName,
  projectNameOfPlace,
  pulse,
  recent,
  REACH_WORD,
  serverReach,
  shared,
  SHARED_SHOWN,
  shownMemory,
  skillReach,
  switcher,
  switchRoute,
  waitingLine,
  workingLine,
} from '../src/core/domain/project-context';

/** Mirrors macos/Tests/MemnoxVoiceCoreTests/Domain/Projects/ProjectContextTests.swift. */
const project = (extra: Partial<ProjectView> = {}): ProjectView => ({
  id: 'p1',
  name: 'Spring launch',
  path: '/work/launch',
  declared: true,
  opened: true,
  agents: [],
  agentsSeen: [],
  sessions: { total: 0, ended: 0 },
  servers: [],
  skills: [],
  rules: { count: 0, inForce: false },
  instructions: [],
  memoryScope: 'project',
  openMissions: [],
  openQuestions: 0,
  ...extra,
});

const site = project({ id: 'p2', name: 'Website', path: '/work/site', lastActive: '2026-11-06T10:00:00Z' });
const launch = project({ lastActive: '2026-11-05T10:00:00Z' });
const now = Date.parse('2026-11-06T12:00:00Z');

function fact(id: string, owner: string | undefined, createdAt = '2026-11-01T00:00:00Z'): MemoryItemView {
  return { id, statement: id, scope: owner === undefined ? 'personal' : 'project', ...(owner === undefined ? {} : { project: owner }), createdAt } as MemoryItemView;
}

function card(fields: Partial<SessionCard>): SessionCard {
  return { sessionId: 's', agent: 'claude-code', agentName: 'Claude Code', state: 'working', thinking: false, ...fields } as SessionCard;
}

describe('what belongs to one project and what is shared', () => {
  it('calls a skill written into this folder only here, the person’s own shared, and another project’s nothing', () => {
    expect(skillReach('project', '/work/launch/.claude', launch)).toBe('only-here');
    expect(skillReach('personal', undefined, launch)).toBe('every-project');
    expect(skillReach('organization', undefined, launch)).toBe('every-project');
    expect(skillReach('project', '/work/site', launch)).toBeUndefined();
    expect(serverReach(true)).toBe('every-project');
    expect(serverReach(false)).toBe('only-here');
    expect(REACH_WORD['only-here']).toBe('Only here');
    expect(REACH_WORD['every-project']).toBe('Every project');
  });

  it('splits memory into what the project learned and what no project owns, never guessing', () => {
    const items = [fact('a', '/work/launch', '2026-11-01T00:00:00Z'), fact('b', '/work/launch/', '2026-11-02T00:00:00Z'), fact('c', undefined), fact('d', '/work/site')];
    expect(memoryReach(fact('x', undefined), launch)).toBe('every-project');
    expect(memoryReach(fact('x', '/work/site'), launch)).toBeUndefined();
    const split = projectMemorySplit(items, launch);
    expect(split.here.map((each) => each.id)).toEqual(['b', 'a']);
    expect(split.everywhere.map((each) => each.id)).toEqual(['c']);
  });

  it('filters the shared Memory page by project and names whose each fact is', () => {
    const items = [fact('a', '/work/launch'), fact('c', undefined), fact('d', '/elsewhere/notes')];
    const projects = [launch, site];
    expect(memoryChoices(projects).map((each) => each.title)).toEqual(['All projects', 'Shared with every project', 'Website', 'Spring launch']);
    expect(shownMemory(items, { kind: 'shared' }, projects).map((each) => each.id)).toEqual(['c']);
    expect(shownMemory(items, { kind: 'project', id: 'p1' }, projects).map((each) => each.id)).toEqual(['a']);
    expect(shownMemory(items, { kind: 'project', id: 'gone' }, projects)).toHaveLength(3);
    expect(items.map((each) => memoryOwner(each, projects))).toEqual(['Spring launch', 'Every project', 'notes']);
    expect(choiceOfKey(choiceKey({ kind: 'shared' }))).toEqual({ kind: 'shared' });
    expect(choiceOfKey(choiceKey({ kind: 'project', id: 'p1' }))).toEqual({ kind: 'project', id: 'p1' });
    expect(choiceOfKey(null)).toEqual({ kind: 'all' });
  });

  it('links the shared group only to pages the daemon answers, each with what applies here', () => {
    const everything: Supports = () => true;
    const links = shared({ rules: 3, skills: 1 }, everything);
    expect(links.map((each) => each.title)).toEqual(['Protection settings', 'Skills', 'MCP servers', 'Connectors', 'Memory', 'AI agents']);
    expect(links[0]?.hint).toBe('3 rules hold here and in every project');
    expect(links[1]?.hint).toBe('1 skill its agents carry in every project');
    // The Overview's Skills part opens this link, the shared My Skills, rather than one of the project's own pages.
    expect(links[1]?.route).toEqual({ destination: 'workspaces', tab: 'skills' });
    expect(links[4]?.route).toEqual({ destination: 'workspaces', tab: 'map' });
    expect(links[2]?.count).toBeUndefined();
    expect(shared({}, () => false).map((each) => each.title)).toEqual(['Connectors', 'AI agents']);
    expect(SHARED_SHOWN).toBe(false);
  });
});

describe('moving between projects', () => {
  it('lists the most recent first and finds one by name or folder', () => {
    expect(recent([launch, site]).map((each) => each.name)).toEqual(['Website', 'Spring launch']);
    expect(matching([launch, site], 'site').map((each) => each.name)).toEqual(['Website']);
    expect(matching([launch, site], 'spring LAUNCH').map((each) => each.name)).toEqual(['Spring launch']);
  });

  it('lights a project where an agent works and keeps the page when switching', () => {
    const rows = switcher([launch, site], [card({ repository: '/work/site/app' })], 'p1', '');
    expect(rows.map((each) => [each.name, each.live, each.current])).toEqual([
      ['Website', true, false],
      ['Spring launch', false, true],
    ]);
    expect(switchRoute('p2', { id: 'p1', page: 'memory' })).toEqual(projectRoute('p2', 'memory'));
    expect(switchRoute('p2', { id: 'p1', page: 'tools' })).toEqual(projectRoute('p2'));
  });

  it('says who works there now, what waits there and when anything last happened', () => {
    const busy = pulse(site, [card({ repository: '/work/site' }), card({ repository: '/other' })], ['site', 'launch', undefined], now);
    expect(workingLine(busy)).toBe('Claude Code working now');
    expect(waitingLine(busy)).toBe('1 waits on you');
    expect(busy.lastActivity).toBe('Active now');
    const quiet = pulse(launch, [], [], now);
    expect(workingLine(quiet)).toBeUndefined();
    expect(quiet.lastActivity).toBe('Active 1 d ago');
    expect(pulse(project({ path: '/new' }), [], [], now).lastActivity).toBe('No activity yet');
  });

  it('names the project a session or a held call happens in, else its folder', () => {
    expect(projectName('/work/site/app', [launch, site])).toBe('Website');
    expect(projectName('/code/other', [launch, site])).toBe('other');
    expect(projectNameOfPlace('launch', [launch, site])).toBe('Spring launch');
    expect(projectNameOfPlace('scratch', [launch])).toBe('scratch');
    expect(projectNameOfPlace(undefined, [launch])).toBeUndefined();
    expect(inLine('Website')).toBe('In Website');
  });
});
