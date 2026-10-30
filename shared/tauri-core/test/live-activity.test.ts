import type { DaemonEvent, LiveActivityRow } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { Home } from '../src/core/application/home';
import { RequestIds } from '../src/core/application/request-ids';
import { Activity } from '../src/core/application/studio';
import { isSaid, isShownOnly } from '../src/core/domain/announcing';
import { agentNameOf, liveMatch, missedRowsLine, MOST_LIVE_ROWS_KEPT, newRowsLine } from '../src/core/domain/live-activity';
import { ScriptedDaemon } from './doubles';

const live = (id: string, extra: Partial<LiveActivityRow> = {}): LiveActivityRow => ({ id, at: '2026-10-30T10:00:00Z', agent: 'claude-code', operation: 'git.push', effect: 'allow', target: 'origin', ...extra });
const paged = (id: string) => ({ id, at: '2026-10-30T09:00:00Z', agent: 'claude-code', agentName: 'Claude Code', session: 's', kind: 'command' as const, operation: 'git.push', effect: 'allow' as const, reason: 'allowed' });

async function activityOn(filter: Parameters<Activity['show']>[0] = {}): Promise<Activity> {
  const daemon = new ScriptedDaemon({ activity: (request) => [{ id: request.id, ok: true, activity: { rows: [paged('old')], nextCursor: 'c1' } }] });
  const activity = new Activity(daemon, new RequestIds());
  await activity.show(filter);
  return activity;
}

describe('a live row against the filter', () => {
  it('is shown, left out, or left to a refresh when names alone cannot tell', () => {
    expect(liveMatch(live('a'), {})).toBe('shown');
    expect(liveMatch(live('a'), { effect: 'deny' })).toBe('hidden');
    expect(liveMatch(live('a'), { agent: 'codex-cli' })).toBe('hidden');
    expect(liveMatch(live('a'), { text: 'ORIGIN' })).toBe('shown');
    expect(liveMatch(live('a'), { text: 'deploy' })).toBe('hidden');
    expect(liveMatch(live('a'), { since: '2026-10-31T00:00:00Z' })).toBe('hidden');
    expect(liveMatch(live('a'), { kind: 'command' })).toBe('unknown');
  });

  it('is worded as the pill and the refresh line say it', () => {
    expect(newRowsLine(3)).toBe('3 new');
    expect(missedRowsLine(4)).toBe('and 4 more, refresh to see them');
    expect(agentNameOf(live('a'), new Map([['claude-code', 'Claude Code']]))).toBe('Claude Code');
    expect(agentNameOf(live('a', { agent: 'cursor' }), new Map())).toBe('cursor');
  });
});

describe('the activity list as rows arrive', () => {
  it('puts matching rows above the first page, newest first, at the top', async () => {
    const activity = await activityOn({ effect: 'allow' });
    activity.heard([live('a'), live('b'), live('c', { effect: 'deny' })], 0);
    expect(activity.live.map((row) => row.id)).toEqual(['b', 'a']);
    expect(activity.rows.map((row) => row.id)).toEqual(['old']);
    expect(activity.more).toBe(true);
  });

  it('holds rows behind the pill while scrolled away, and shows them when pressed', async () => {
    const activity = await activityOn();
    activity.atTop(false);
    activity.heard([live('a'), live('b')], 0);
    expect(activity.live).toEqual([]);
    expect(activity.waiting).toBe(2);
    activity.showWaiting();
    expect(activity.live.map((row) => row.id)).toEqual(['b', 'a']);
    expect(activity.waiting).toBe(0);
    activity.heard([live('c')], 0);
    activity.atTop(true);
    expect(activity.live.map((row) => row.id)).toEqual(['c', 'b', 'a']);
  });

  it('counts what a burst did not carry or could not place, and forgets it on a refresh', async () => {
    const activity = await activityOn({ kind: 'command' });
    activity.heard([live('a')], 5);
    expect(activity.live).toEqual([]);
    expect(activity.missed).toBe(6);
    await activity.show({});
    expect(activity.missed).toBe(0);
  });

  it('never shows a row twice, and keeps the live rows bounded', async () => {
    const activity = await activityOn();
    activity.heard([live('old'), live('a')], 0);
    activity.heard([live('a')], 0);
    expect(activity.live.map((row) => row.id)).toEqual(['a']);
    activity.heard(Array.from({ length: MOST_LIVE_ROWS_KEPT + 3 }, (_, at) => live(`n${at}`)), 0);
    expect(activity.live).toHaveLength(MOST_LIVE_ROWS_KEPT);
    expect(activity.missed).toBe(4);
  });
});

describe('live activity elsewhere', () => {
  it('counts into today on Home without reading again', async () => {
    const view = { machine: 'm', mode: 'enforce', waiting: 0, working: [], today: { actions: 4, asked: 0, allowed: 0, refused: 0 }, notCovered: { unprotected: 0, dormant: 0 } };
    const daemon = new ScriptedDaemon({ home: (request) => [{ id: request.id, ok: true, home: view }] });
    const home = new Home(daemon, new RequestIds(), async () => undefined);
    await home.refresh();
    home.heard(3);
    expect(home.home?.today.actions).toBe(7);
    expect(daemon.sent('home')).toHaveLength(1);
  });

  it('is never said by the voice', () => {
    const event: DaemonEvent = { kind: 'activity', subject: 'a', agent: 'claude-code', summary: '2 actions', at: 't', activityRows: [live('a')] };
    expect(isShownOnly(event)).toBe(true);
    expect(isSaid(event, true)).toBe(false);
  });
});
