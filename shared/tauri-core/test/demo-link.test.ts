import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { requestOnce } from '../src/core/application/ports/daemon-link';
import { activityWords } from '../src/core/domain/activity-words';
import { demoStamp, DemoLink, isoSecond } from '../src/ui/adapters/demo-link';

/** The one demo world both desktop apps read; the Mac's DemoLinkTests decodes it through the Swift protocol. */
const shared = fileURLToPath(new URL('../../demo/power-user.json', import.meta.url));
const fixture = JSON.parse(readFileSync(shared, 'utf8')) as { answers: Record<string, Record<string, unknown>>; held: unknown[]; memory: unknown[] };
const now = new Date('2026-11-06T15:00:00Z');
const link = () => new DemoLink(fixture, () => now);
const ask = (demo: DemoLink, method: string, more: Partial<DaemonRequest> = {}): Promise<DaemonResponse> =>
  requestOnce(demo, { id: 7, method, ...more } as DaemonRequest);

describe('the demo world', () => {
  it('answers every method it names, with the id asked', async () => {
    const demo = link();
    for (const method of Object.keys(fixture.answers)) {
      const response = await ask(demo, method);
      expect(response.id, method).toBe(7);
    }
  });

  it('holds a power user’s day', async () => {
    const demo = link();
    const projects = (await ask(demo, 'projects')).projects?.projects ?? [];
    expect(projects).toHaveLength(7);
    expect(projects.filter((each) => each.organization !== undefined)).toHaveLength(1);
    expect((await ask(demo, 'waiting')).waiting).toHaveLength(5);
    expect(new Set((await ask(demo, 'agents')).agentsView?.map((each) => each.kind))).toEqual(new Set(['claude-code', 'codex-cli', 'cursor', 'gemini-cli', 'windsurf']));
    expect((await ask(demo, 'activity')).activity?.rows).toHaveLength(60);
    expect((await ask(demo, 'rules')).policyRules?.rules.length).toBeGreaterThanOrEqual(25);
    expect((await ask(demo, 'skills-hub')).skillsHub?.skills.length).toBeGreaterThanOrEqual(40);
    expect((await ask(demo, 'mcp-hub')).mcpHub?.servers).toHaveLength(10);
    expect((await ask(demo, 'connections-list')).connections?.filter((each) => each.connected)).toHaveLength(8);
    expect((await ask(demo, 'memory-sources')).memorySources).toHaveLength(10);
    expect((await ask(demo, 'memory-facts')).memoryFacts?.items.length).toBeGreaterThanOrEqual(45);
    expect((await ask(demo, 'memory-learn')).memoryLearn?.items.length).toBeGreaterThan(0);
    expect((await ask(demo, 'devices-list')).devices).toHaveLength(1);
    expect((await ask(demo, 'machine')).machine?.name).toBe('Acme');
    expect(demo.personName).toBe('Alex Rivera');
  });

  it('writes every time as a moment before the app opened', async () => {
    const rows = (await ask(link(), 'activity')).activity?.rows ?? [];
    for (const row of rows) expect(Date.parse(row.at)).toBeLessThanOrEqual(now.getTime());
    expect(demoStamp('$now-5m', now)).toBe(isoSecond(new Date(now.getTime() - 300_000)));
    expect(demoStamp('$now+2d', now)).toBe(isoSecond(new Date(now.getTime() + 172_800_000)));
    expect(demoStamp('$nowhere', now)).toBeUndefined();
  });

  it('says every ledger row in words Today can show', async () => {
    for (const row of (await ask(link(), 'activity')).activity?.rows ?? []) expect(activityWords(row)).not.toBe('');
  });

  it('narrows the ledger as Activity and Today ask for it', async () => {
    const demo = link();
    const refused = (await ask(demo, 'activity', { activityFilter: { effect: 'deny' } })).activity?.rows ?? [];
    expect(refused.length).toBeGreaterThan(0);
    expect(refused.every((row) => row.effect === 'deny')).toBe(true);
    const lastHour = (await ask(demo, 'activity', { activityFilter: { since: isoSecond(new Date(now.getTime() - 3_600_000)) } })).activity?.rows ?? [];
    expect(lastHour.length).toBeLessThan(60);
  });

  it('settles an answered call here alone, and tells the subscription', async () => {
    const demo = link();
    const feed = demo.stream({ id: 9, method: 'subscribe' } as DaemonRequest)[Symbol.asyncIterator]();
    const opening: string[] = [];
    for (let index = 0; index < 6; index++) opening.push((await feed.next()).value?.event?.kind ?? '');
    expect(opening.filter((kind) => kind === 'held')).toHaveLength(5);
    expect(opening.at(-1)).toBe('notice');
    expect((await ask(demo, 'confirm', { subject: 'hold_web_push_main', answer: 'once' })).ok).toBe(true);
    expect((await feed.next()).value?.event).toMatchObject({ kind: 'settled', subject: 'hold_web_push_main' });
    expect((await ask(demo, 'waiting')).waiting).toHaveLength(4);
    expect((await ask(demo, 'home')).home?.waiting).toBe(4);
    await feed.return?.();
  });

  it('answers a write with its page and refuses what only a daemon can do', async () => {
    const demo = link();
    expect((await ask(demo, 'rule-propose')).policyRules?.rules.length).toBeGreaterThan(0);
    const signIn = await ask(demo, 'connections-sign-in');
    expect(signIn.ok).toBe(false);
    expect(signIn.error).toBe(demo.demoOnly);
  });

  it('keeps every dash out of its copy', () => {
    expect(readFileSync(shared, 'utf8')).not.toMatch(/[\u2013\u2014]| - /);
  });
});
