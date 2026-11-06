import type { ActivityRow, AgentView, SessionCard } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import {
  age,
  choiceFor,
  done,
  handoffs,
  headline,
  heldChoices,
  log,
  openProjects,
  overview,
  position,
  sections,
  signs,
  step,
  stripLine,
  waited,
  waitsLine,
  under,
  type TodaySources,
} from '../src/core/domain/today-board';

const now = new Date(2026, 10, 1, 13, 14).getTime();
const at = (minutesAgo: number) => new Date(now - minutesAgo * 60_000).toISOString();
const yesterday = new Date(2026, 9, 31, 22, 0).toISOString();

function row(id: string, fields: Partial<ActivityRow>): ActivityRow {
  return { id, at: at(5), agent: 'claude-code', agentName: 'Claude Code', session: 's1', kind: 'shell', operation: 'run', target: 'npm test', effect: 'allow', reason: 'allowed', ...fields } as ActivityRow;
}

function card(sessionId: string, fields: Partial<SessionCard>): SessionCard {
  return { sessionId, agent: 'codex', agentName: 'Codex', state: 'working', thinking: false, repository: '/code/memnox', lastActive: at(1), ...fields } as SessionCard;
}

const empty: TodaySources = { held: [], sessions: [], activity: [], agents: [], owed: [] };

describe('Today', () => {
  it('puts held calls and refusals first, then what stopped, what waits and what is next, oldest first within each', () => {
    const items = overview(
      {
        ...empty,
        held: [{ subject: 'h1', agent: 'codex', who: 'Codex', what: 'push to main', at: at(2) }],
        activity: [row('r1', { effect: 'deny', rule: 'no pushes', at: at(30) }), row('r2', { effect: 'deny', rule: 'no pushes', at: at(10) }), row('r3', { failed: 2, at: at(3) })],
        sessions: [card('s-paused', { state: 'paused' }), card('s-working', {})],
        owed: ['Approve the hooks in Codex'],
        agents: [{ kind: 'cursor', name: 'Cursor', status: 'unprotected' } as AgentView],
        ready: { action: 'npm test', approvals: 12, targets: [], because: 'You always said yes' },
      },
      now,
    );
    expect(items.map((item) => item.id)).toEqual(['stopped:r2', 'held:h1', 'stopped:r3', 'session:s-paused', 'owed:Approve the hooks in Codex', 'unprotected:cursor', 'ready:npm test', 'session:s-working']);
    expect(items[0]?.detail).toBe('Refused by no pushes, 2 times today');
    expect(sections(items).map((group) => [group.section, group.items.length])).toEqual([
      ['needs-you', 4],
      ['next', 3],
      ['working', 1],
    ]);
  });

  it('reads only today from the ledger, newest first, for Done and the Log', () => {
    const rows = [row('old', { at: yesterday }), row('a', { at: at(20) }), row('b', { at: at(2) }), row('denied', { effect: 'deny', at: at(1) }), row('asked', { effect: 'ask', at: at(4) })];
    expect(done(rows, now).map((item) => item.id)).toEqual(['row:b', 'row:a']);
    expect(log(rows, now).map((item) => [item.id, item.state])).toEqual([
      ['row:denied', 'stopped'],
      ['row:b', 'done'],
      ['row:asked', 'needs-you'],
      ['row:a', 'done'],
    ]);
  });

  it('hands back what a session handed back and the runtime’s own suggestion, which it recommends', () => {
    const items = handoffs({ ...empty, sessions: [card('back', { state: 'open' }), card('busy', {})], ready: { action: 'git status', approvals: 9, agentName: 'Codex', targets: [], because: 'nine yeses' } });
    expect(items.map((item) => item.id)).toEqual(['session:back', 'ready:git status']);
    const ready = items.find((item) => item.id === 'ready:git status');
    expect(ready?.recommendation).toBe('nine yeses');
    expect(ready?.choices[0]).toMatchObject({ key: 'A', title: 'Hand it over', recommended: true });
  });

  it('offers a held call the island’s answers, leaving from now on off a teammate’s', () => {
    expect(heldChoices(false).map((choice) => `${choice.key} ${choice.title}`)).toEqual(['A Allow once', 'B Allow this session', 'C Allow from now on', 'D Deny']);
    expect(heldChoices(true).map((choice) => choice.title)).toEqual(['Allow once', 'Allow this session', 'Deny']);
  });

  it('signs every allow unless the daemon placed the call inside its session, and never a deny', () => {
    const [once, , , deny] = heldChoices(false);
    expect(once !== undefined && signs(once, true)).toBe(true);
    expect(once !== undefined && signs(once, undefined)).toBe(true);
    expect(once !== undefined && signs(once, false)).toBe(false);
    expect(deny !== undefined && signs(deny, true)).toBe(false);
  });

  it('steps through the items and stops at either end, and presses a choice by its letter in either case', () => {
    const items = overview({ ...empty, held: [{ subject: 'a', agent: 'x', who: 'X', what: 'one' }, { subject: 'b', agent: 'x', who: 'X', what: 'two' }] }, now);
    expect(step(undefined, 1, items)).toBe('held:a');
    expect(step('held:a', 1, items)).toBe('held:b');
    expect(step('held:b', 1, items)).toBe('held:b');
    expect(step('held:a', -1, items)).toBe('held:a');
    expect(items[0] !== undefined && choiceFor('d', items[0])?.title).toBe('Deny');
    expect(position('held:b', items)).toBe('2 of 2');
  });

  it('says the day, the strip and the ages in the Mac’s words', () => {
    expect(headline(now, 13, 1, 7)).toBe('1 Nov. 13 need you, 1 next, 7 open projects');
    expect(headline(now, 0, 0, 1)).toBe('1 Nov. nothing needs you, 0 next, 1 open project');
    expect(stripLine(13, 5)).toBe('13 need you, the 5 most urgent here');
    expect(stripLine(1, 1)).toBe('1 needs you');
    expect(age(now - 4_000, now)).toBe('now');
    expect(age(now - 4 * 60_000, now)).toBe('4 min');
    expect(waited(undefined, now)).toBe('Not recorded');
    const items = overview({ ...empty, held: [{ subject: 'a', agent: 'x', who: 'X', what: 'one' }], sessions: [card('p', { state: 'paused' })] }, now);
    expect(waitsLine(items)).toBe('1 held call, 1 stopped');
  });

  it('counts the repositories a session is still open in', () => {
    expect(openProjects([card('a', {}), card('b', {}), card('c', { repository: '/code/other' })])).toBe(2);
  });
});

describe('naming the project each item happens in', () => {
  it('names a held call by its folder and a session by its repository, so several projects stay apart', () => {
    const projects = [{ id: 'p1', name: 'Memnox app', path: '/code/memnox', declared: true, opened: true, agents: [], agentsSeen: [], sessions: { total: 0, ended: 0 }, servers: [], skills: [], rules: { count: 0, inForce: false }, instructions: [], memoryScope: 'project', openMissions: [], openQuestions: 0 }];
    const items = overview({ ...empty, held: [{ subject: 'h', agent: 'x', who: 'X', what: 'push', why: 'pushes main', place: 'memnox' }], sessions: [card('s', {})], projects }, now);
    expect(items.map((item) => item.project)).toEqual(['Memnox app', 'Memnox app']);
    expect(items.map((item) => under(item))).toEqual(['In Memnox app · pushes main', 'In Memnox app']);
  });
});
