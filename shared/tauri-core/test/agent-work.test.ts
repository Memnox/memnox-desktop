import type { ProfileView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { AgentWorkDesk } from '../src/core/application/agent-work';
import { RequestIds } from '../src/core/application/request-ids';
import { NO_LEVELS, type AgentWork } from '../src/core/domain/agent-wire';
import { currentWork, issueLine, needsYou, orderedProfiles, purposeLine, workLink } from '../src/core/domain/agent-work-lines';
import { ScriptedDaemon } from './doubles';

function work(id: string, status: AgentWork['status'] = 'active', extra: Partial<AgentWork> = {}): AgentWork {
  return {
    id,
    profileId: 'backend',
    responsiblePerson: 'Bo',
    target: { source: 'linear', externalId: 'LIN-1' },
    sessions: [],
    attempts: 1,
    status,
    progress: [],
    handoffs: [],
    createdAt: '2026-11-07T09:00:00Z',
    updatedAt: '2026-11-07T09:00:00Z',
    ...extra,
  };
}

function profile(id: string, extra: Partial<ProfileView> = {}): ProfileView {
  return { id, name: id, skills: [], mcpServers: [], updatedAt: '', missing: [], responsibilities: [], projects: [], connections: [], levels: NO_LEVELS, ...extra };
}

describe('agent work on Windows and Linux', () => {
  it('starts, stops and answers with no signature, leaving a blank title unsent', async () => {
    const daemon = new ScriptedDaemon({
      'agent-work': (request) => [{ id: request.id, ok: true, agentWork: [work('agw_1')] }],
      'work-start': (request) => [{ id: request.id, ok: true, agentWork: [work('agw_2'), work('agw_1')] }],
      'handoff-answer': (request) => [{ id: request.id, ok: false, error: 'No handoff waits under that id.' }],
    });
    const desk = new AgentWorkDesk(daemon, new RequestIds());
    await desk.refresh();
    expect(desk.work?.map((each) => each.id)).toEqual(['agw_1']);
    expect(await desk.start('backend', ' LIN-2 ', { title: ' ', project: '/code/api' })).toEqual({ kind: 'done', note: 'Started on LIN-2. The agent sees it at its next pause.' });
    const start = daemon.sent('work-start')[0];
    expect(start?.workTarget).toBe('LIN-2');
    expect(start?.workTitle).toBeUndefined();
    expect(start?.workProject).toBe('/code/api');
    expect(start?.signature).toBeUndefined();
    expect(await desk.answer('hnd_1', 'accept')).toEqual({ kind: 'failed', why: 'No handoff waits under that id.' });
    expect(daemon.sent('handoff-answer')[0]?.handoffAnswer).toBe('accept');
  });

  it('names the issue, opens only a web link and keeps finished work off an agent', () => {
    expect(issueLine(work('a', 'active', { target: { source: 'linear', externalId: 'LIN-1', title: 'Fix login' } }))).toBe('LIN-1 · Fix login');
    expect(workLink(work('a', 'active', { target: { source: 'linear', externalId: 'LIN-1', url: 'file:///etc/passwd' } }))).toBeUndefined();
    expect(currentWork('backend', [work('a', 'done'), work('b', 'done_claimed')])?.id).toBe('b');
    expect(needsYou(work('b', 'done_claimed'))).toBe(true);
  });

  it('orders jobs before defaults before jobs with nobody behind them', () => {
    const connection = { id: 'con_c', profileId: 'p', kind: 'runtime_hook', mediation: 'interposed', firstSeen: '', lastSeen: '', status: 'live' } as const;
    const ordered = orderedProfiles([profile('review'), profile('default:codex', { isDefault: true, connections: [connection] }), profile('backend', { connections: [connection] })]);
    expect(ordered.map((each) => each.id)).toEqual(['backend', 'default:codex', 'review']);
    expect(purposeLine(profile('x', { isDefault: true }))).toBe('No job yet.');
  });
});
