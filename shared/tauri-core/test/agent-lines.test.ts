import type { AgentView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import {
  actionTarget,
  afterProtect,
  agentFigures,
  agentFilters,
  agentPress,
  agentsSummary,
  filterCount,
  needsProtecting,
  noneShown,
  reachLine,
  runtimePredatesSeams,
  shownAgents,
  skillChips,
  unprotectedKinds,
} from '../src/core/domain/agent-lines';

function agent(kind: string, name: string, status: AgentView['status'], more: Partial<AgentView> = {}): AgentView {
  return {
    kind,
    name,
    status,
    sessions: { running: 0, idle: 0, finished: 0 },
    mcpServers: [],
    skills: [],
    today: { actions: 0, asked: 0, refused: 0 },
    recent: [],
    launchable: false,
    ...more,
  };
}

/** The same three agents as the Mac's AgentLinesTests, so both pin the same words. */
const list: AgentView[] = [
  agent('code', 'Claude Code', 'protected', { sessions: { running: 1, idle: 0, finished: 3 }, today: { actions: 12, asked: 2, refused: 0 } }),
  agent('desk', 'Claude Desktop', 'unprotected'),
  agent('cur', 'Cursor', 'protected', { sessions: { running: 0, idle: 2, finished: 0 } }),
];

describe('the Agents page lines, as the Mac says them', () => {
  it('sums up the page in counts', () => {
    expect(agentsSummary(list)).toBe('3 agents, 2 protected, 1 running');
  });

  it('offers Running and Paused always and Not protected only while some agent is', () => {
    expect(agentFilters(list)).toEqual(['all', 'running', 'unprotected', 'paused']);
    expect(agentFilters([list[0] as AgentView])).toEqual(['all', 'running', 'paused']);
    expect(filterCount(list, 'paused')).toBe(0);
    expect(shownAgents(list, 'all').map((each) => each.kind)).toEqual(['desk', 'code', 'cur']);
    expect(shownAgents(list, 'running').map((each) => each.kind)).toEqual(['code']);
    expect(filterCount(list, 'unprotected')).toBe(1);
    expect(noneShown('paused')).toBe('No agent is paused.');
  });

  it('shows only the numbers that say something', () => {
    expect(agentFigures(list[0] as AgentView).map((each) => each.label)).toEqual(['Running', 'Today', 'Asked']);
    expect(agentFigures(list[0] as AgentView).map((each) => each.value)).toEqual([1, 12, 2]);
    expect(agentFigures(list[2] as AgentView)).toEqual([]);
  });

  it('names the agents running outside Memnox', () => {
    expect(needsProtecting(list)).toBe('Claude Desktop is not protected');
    expect(needsProtecting([])).toBeUndefined();
    expect(unprotectedKinds(list)).toEqual(['desk']);
  });

  it('names a target by its last parts', () => {
    expect(actionTarget({ target: '/Users/me/code/Memnox-saas/app/main.swift' })).toBe('app/main.swift');
    expect(actionTarget({ target: ' ' })).toBeUndefined();
  });

  it('leads with Protect for an agent outside Memnox', () => {
    expect(agentPress(list[0] as AgentView)).toBe('pause');
    expect(agentPress(list[1] as AgentView)).toBe('protect');
    expect(agentPress(agent('p', 'P', 'paused'))).toBe('resume');
  });

  it('says when it was last active and what it reaches', () => {
    const busy = agent('code', 'Claude Code', 'protected', {
      mcpServers: ['github'],
      skills: ['a', 'b'],
      recent: [{ id: '1', at: '2026-10-28T10:00:00Z', operation: 'git.push', effect: 'allow' }],
    });
    const now = Date.parse('2026-10-31T10:00:00Z');
    expect(reachLine(busy, now)).toBe('Last active 3 d ago · 2 skills · 1 MCP server');
    expect(reachLine(list[1] as AgentView, now)).toBe('No activity seen yet · 0 skills · 0 MCP servers');
  });

  it('shows a few skills as chips and counts the rest', () => {
    expect(skillChips(['a', 'b', 'c', 'd'], 3)).toEqual({ shown: ['a', 'b', 'c'], more: 1 });
    expect(skillChips(undefined, 3)).toEqual({ shown: [], more: 0 });
  });
});

describe('what a Protect press came to', () => {
  const desktop = (status: AgentView['status'], seam?: 'hook' | 'servers') => agent('claude-desktop', 'Claude Desktop', status, seam === undefined ? {} : { seam });
  const code = agent('claude-code', 'Claude Code', 'protected', { seam: 'hook' });

  it('says to reopen an agent held through its servers once it is protected', () => {
    const result = afterProtect(['claude-desktop'], [desktop('protected', 'servers')], undefined);
    expect(result.held).toBe(true);
    expect(result.line).toBe('Claude Desktop is protected. Quit and open Claude Desktop again so its servers start through Memnox.');
  });

  it('says what still keeps an agent outside', () => {
    expect(afterProtect(['claude-desktop'], [desktop('unprotected', 'servers')], undefined).line.startsWith('Claude Desktop still starts a server outside Memnox')).toBe(true);
    const none = afterProtect(['claude-desktop'], [code, desktop('unprotected')], undefined);
    expect(none.line).toBe('Memnox has no way into Claude Desktop yet, so Protect cannot hold it.');
    expect(none.restartService).toBe(false);
    expect(afterProtect(['claude-desktop'], [desktop('unprotected', 'hook')], undefined).line).toContain('its hook did not go in');
  });

  it('offers a restart when the service is too old to see an agent is held', () => {
    const old = [desktop('unprotected')];
    expect(runtimePredatesSeams(old)).toBe(true);
    const result = afterProtect(['claude-desktop'], old, undefined);
    expect(result.restartService).toBe(true);
    expect(result.line).toBe('The Memnox service on this computer is older than this app, so it cannot see that Claude Desktop is held. Restart it to run the newer runtime.');
    expect(runtimePredatesSeams([code, desktop('unprotected')])).toBe(false);
    expect(runtimePredatesSeams([])).toBe(false);
  });

  it('carries the reason a Protect failed', () => {
    expect(afterProtect(['claude-desktop'], [desktop('protected', 'hook')], 'No memnox here.')).toEqual({ kinds: ['claude-desktop'], line: 'No memnox here.', held: false, restartService: false });
  });
});
