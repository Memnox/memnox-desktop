import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { McpHub } from '../src/core/application/mcp-hub';
import { LONGEST_PRESS_MS, MOST_PRESSES, PRESS_GRACE_MS, PRESS_LIFETIME_MS, Presses, PressingLink, type Press } from '../src/core/application/presses';
import { requestOnce } from '../src/core/application/ports/daemon-link';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking } from '../src/core/application/talking';
import { HandTimer, held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

/** A clock the waits move on, so a test never sleeps for real. */
function clocked(slept: (presses: Presses) => void = () => undefined) {
  const clock = { at: 1_000_000 };
  const presses: Presses = new Presses(
    async (ms) => {
      clock.at += ms;
      slept(presses);
      await Promise.resolve();
    },
    () => clock.at,
  );
  return { clock, presses };
}

function island(slept?: (presses: Presses) => void) {
  const { clock, presses } = clocked(slept);
  const daemon = new ScriptedDaemon({ 'register-key': registered, confirm: (request) => [{ id: request.id, ok: true }] });
  const key = new PersonKey();
  const ids = new RequestIds();
  const talking = new Talking(daemon, new RecordingSpeaker(), new Signer(daemon, key, ids), ids, { now: () => clock.at, timer: new HandTimer().start, presses });
  return { clock, presses, daemon, key, talking };
}

const proposal = (subject: string): DaemonEvent => ({ ...held(subject), kind: 'proposal', summary: 'keep GITHUB_TOKEN' });
const answering = (response: Partial<DaemonResponse>) => (request: DaemonRequest): DaemonResponse[] => [{ id: request.id, ok: true, ...response }];
const declined = (daemon: ScriptedDaemon) => daemon.sent('confirm').some((request) => request.answer === 'declined');

describe('a press in the Memnox window', () => {
  it('tells the island it began and then the proposals its answer made', async () => {
    const told: Press[] = [];
    const window = new ScriptedDaemon({ 'rule-pack-import': answering({ packProposed: ['prp_a', 'prp_b'] }) });
    const link = new PressingLink(window, (press) => told.push(press), () => 'tok');
    await requestOnce(link, { id: 1, method: 'rule-pack-import' });
    expect(told).toEqual([{ token: 'tok' }, { token: 'tok', raised: ['prp_a', 'prp_b'] }]);
  });

  it('says it ended with nothing raised when the daemon never answered', async () => {
    const told: Press[] = [];
    const link = new PressingLink(new ScriptedDaemon({}), (press) => told.push(press), () => 'tok');
    await expect(requestOnce(link, { id: 1, method: 'mcp-server-put' })).rejects.toThrow();
    expect(told).toEqual([{ token: 'tok' }, { token: 'tok', raised: [] }]);
  });

  it('is not a background read, which never makes a proposal wait', async () => {
    const told: Press[] = [];
    const window = new ScriptedDaemon({ 'mcp-hub': answering({}) });
    const link = new PressingLink(window, (press) => told.push(press), () => 'tok');
    await requestOnce(link, { id: 1, method: 'mcp-hub' });
    expect(told).toEqual([]);
  });

  it('still notes a proposal any answer names, whatever the method', async () => {
    const told: Press[] = [];
    const window = new ScriptedDaemon({ 'mcp-secret-set': answering({ proposed: 'prp_secret' }) });
    const link = new PressingLink(window, (press) => told.push(press), () => 'tok');
    await requestOnce(link, { id: 1, method: 'mcp-secret-set' });
    expect(told).toEqual([{ token: 'tok', raised: ['prp_secret'] }]);
  });

  it('lets a polled read leave an unasked proposal declined after the grace rather than the longest wait', async () => {
    const { clock, presses, daemon, talking } = island();
    // A read the daemon is slow to answer, as a poll behind a busy page is.
    const window = {
      async *stream(): AsyncIterable<DaemonResponse> {
        await new Promise<void>(() => undefined);
      },
    };
    const link = new PressingLink(window, (press) => presses.heard(press), () => 'tok');
    void requestOnce(link, { id: 1, method: 'mcp-hub' }).catch(() => undefined);
    const began = clock.at;
    await talking.handle(proposal('prp_unasked'));
    expect(declined(daemon)).toBe(true);
    expect(clock.at - began).toBeLessThan(LONGEST_PRESS_MS);
  });

  it('has the island put the proposal it raised to the key', async () => {
    const { presses, daemon, key, talking } = island();
    const window = new ScriptedDaemon({ 'mcp-secret-set': answering({ proposed: 'prp_secret' }) });
    const hub = new McpHub(new PressingLink(window, (press) => presses.heard(press), () => 'tok'), new RequestIds());
    await hub.setSecret('GITHUB_TOKEN', 'v');
    await talking.handle(proposal('prp_secret'));
    expect(declined(daemon)).toBe(false);
    expect(key.signed.map((signed) => signed.message)).toEqual(['memnox-confirm:v1:prp_secret:confirmed']);
  });

  it('still has the island decline a proposal nobody pressed for', async () => {
    const { presses, daemon, key, talking } = island();
    presses.heard({ token: 't', raised: ['prp_secret'] });
    await talking.handle(proposal('prp_other'));
    expect(declined(daemon)).toBe(true);
    expect(key.signed).toEqual([]);
  });

  it('is honoured when it is answered after the proposal arrived, within the wait', async () => {
    let waited = 0;
    // The answer naming it lands while the island is already waiting, half way through the grace.
    const { daemon, key, talking } = island((presses) => {
      waited += 1;
      if (waited === 40) presses.heard({ token: 't', raised: ['prp_late'] });
    });
    await talking.handle(proposal('prp_late'));
    expect(waited).toBe(40);
    expect(declined(daemon)).toBe(false);
    expect(key.signed.map((signed) => signed.message)).toEqual(['memnox-confirm:v1:prp_late:confirmed']);
  });

  it('is not honoured once it has waited past its lifetime', async () => {
    const { clock, presses, daemon, key, talking } = island();
    presses.heard({ token: 't', raised: ['prp_old'] });
    clock.at += PRESS_LIFETIME_MS;
    await talking.handle(proposal('prp_old'));
    expect(declined(daemon)).toBe(true);
    expect(key.signed).toEqual([]);
  });
});

describe('the island waiting on a press', () => {
  it('gives up after the grace when nothing is in flight', async () => {
    const { clock, presses } = clocked();
    const began = clock.at;
    expect(await presses.take('prp_1')).toBe(false);
    expect(clock.at - began).toBeGreaterThanOrEqual(PRESS_GRACE_MS);
    expect(clock.at - began).toBeLessThan(LONGEST_PRESS_MS);
  });

  it('waits longer while a press is unanswered, and never past the longest wait', async () => {
    const { clock, presses } = clocked();
    presses.heard({ token: 'slow' });
    const began = clock.at;
    expect(await presses.take('prp_1')).toBe(false);
    expect(clock.at - began).toBeGreaterThanOrEqual(LONGEST_PRESS_MS);
  });

  it('takes a proposal once', async () => {
    const { presses } = clocked();
    presses.heard({ token: 't', raised: ['prp_1'] });
    expect(await presses.take('prp_1')).toBe(true);
    expect(await presses.take('prp_1')).toBe(false);
  });

  it('keeps only the newest presses', async () => {
    const { presses } = clocked();
    presses.heard({ token: 'a', raised: ['prp_first'] });
    presses.heard({ token: 'b', raised: Array.from({ length: MOST_PRESSES }, (_, n) => `prp_${n}`) });
    expect(await presses.take('prp_first')).toBe(false);
    expect(await presses.take(`prp_${MOST_PRESSES - 1}`)).toBe(true);
  });

  it('does not wait on a start that arrived after its own answer', async () => {
    const { clock, presses } = clocked();
    presses.heard({ token: 't', raised: [] });
    presses.heard({ token: 't' });
    const began = clock.at;
    await presses.take('prp_1');
    expect(clock.at - began).toBeLessThan(LONGEST_PRESS_MS);
  });
});
