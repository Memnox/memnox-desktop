import { describe, expect, it } from 'vitest';
import type { HeldCalls } from '../src/core/application/held-calls';
import { NO_KEY_LINE } from '../src/core/application/signer';
import { ANOTHER_KEY_LINE } from '../src/core/domain/key-status';
import { held, heldCallsOver, PersonKey, registered, ScriptedDaemon } from './doubles';

const confirmed = { confirm: (request: { id: number }) => [{ id: request.id, ok: true, outcome: 'allowed' }] };
const nothingWaits = { waiting: (request: { id: number }) => [{ id: request.id, ok: true, waiting: [] }] };

describe('what the island shows', () => {
  it('puts what already waited and what is held later in the queue, newest on screen', async () => {
    const daemon = new ScriptedDaemon({
      waiting: (request) => [{ id: request.id, ok: true, waiting: [held('hld_1')] }],
    });
    daemon.push(held('hld_2', { agentName: 'Claude Code' }));
    const calls = heldCallsOver(daemon, new PersonKey());
    await calls.watch();
    expect(calls.state.waiting.count).toBe(2);
    expect(calls.state.waiting.shown?.card.label).toBe('Claude Code on this computer');
  });

  it('takes a call off the queue once it is settled elsewhere', async () => {
    const daemon = new ScriptedDaemon(nothingWaits);
    daemon.push(held('hld_1'));
    daemon.push({ ...held('hld_1'), kind: 'settled' });
    const calls = heldCallsOver(daemon, new PersonKey());
    await calls.watch();
    expect(calls.state.waiting.count).toBe(0);
  });

  it('never puts a proposal to the key, since this app has heard no words asking for one', async () => {
    const daemon = new ScriptedDaemon(nothingWaits);
    daemon.push({ ...held('prp_1'), kind: 'proposal' });
    const key = new PersonKey();
    const calls = heldCallsOver(daemon, key);
    await calls.watch();
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')).toEqual([]);
  });

  it('says the feed is closed when the daemon is down', async () => {
    const calls = heldCallsOver(new ScriptedDaemon(), new PersonKey());
    await calls.watch();
    expect(calls.state.connected).toBe(false);
  });
});

describe('answering a held call', () => {
  async function waitingOn(...events: ReturnType<typeof held>[]): Promise<{ daemon: ScriptedDaemon; calls: HeldCalls; key: PersonKey }> {
    const daemon = new ScriptedDaemon({ ...nothingWaits, ...confirmed, 'register-key': registered });
    for (const event of events) daemon.push(event);
    const key = new PersonKey();
    const calls = heldCallsOver(daemon, key);
    await calls.watch();
    return { daemon, calls, key };
  }

  it('signs exactly this call and this answer, and sends the signature with it', async () => {
    const { daemon, calls, key } = await waitingOn(held('hld_1'));
    expect(await calls.answer('hld_1', 'once')).toEqual({ kind: 'answered' });
    expect(key.signed[0]?.message).toBe('memnox-confirm:v1:hld_1:once');
    expect(daemon.sent('confirm')[0]).toMatchObject({ subject: 'hld_1', answer: 'once', signature: 'sig(memnox-confirm:v1:hld_1:once)' });
    expect(calls.state.waiting.count).toBe(0);
  });

  it('tells the person how far the yes reaches before they give it', async () => {
    const { calls, key } = await waitingOn(held('hld_1'));
    await calls.answer('hld_1', 'session');
    expect(key.signed[0]?.reason).toBe('allow codex on this computer for this session: push to main');
  });

  it('sends a deny with no signature, since saying no needs no proof', async () => {
    const { daemon, calls, key } = await waitingOn(held('hld_1'));
    await calls.answer('hld_1', 'deny');
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')[0]?.signature).toBeUndefined();
  });

  it('lets a call the daemon kept inside its session through without the key', async () => {
    const { daemon, calls, key } = await waitingOn(held('hld_1', { withinSession: true }));
    await calls.answer('hld_1', 'once');
    expect(key.signed).toEqual([]);
    expect(daemon.sent('confirm')).toHaveLength(1);
  });

  it('signs for a card it no longer has, since only the daemon can waive the key', async () => {
    const { calls, key } = await waitingOn();
    await calls.answer('hld_gone', 'once');
    expect(key.signed).toHaveLength(1);
  });

  it('sends nothing when the person cancels the prompt', async () => {
    const daemon = new ScriptedDaemon({ ...nothingWaits, 'register-key': registered });
    daemon.push(held('hld_1'));
    const calls = heldCallsOver(daemon, new PersonKey('BPOINT', false));
    await calls.watch();
    expect(await calls.answer('hld_1', 'once')).toEqual({ kind: 'cancelled' });
    expect(daemon.sent('confirm')).toEqual([]);
    expect(calls.state.waiting.count).toBe(1);
  });

  it('never raises the prompt while the daemon trusts another key', async () => {
    const daemon = new ScriptedDaemon({
      ...nothingWaits,
      'register-key': (request) => [{ id: request.id, ok: false, outcome: 'another key' }],
    });
    const key = new PersonKey();
    const calls = heldCallsOver(daemon, key);
    expect(await calls.answer('hld_1', 'once')).toEqual({ kind: 'failed', why: ANOTHER_KEY_LINE });
    expect(key.signed).toEqual([]);
  });

  it('keeps every allow in the terminal on a computer with no key', async () => {
    const daemon = new ScriptedDaemon(nothingWaits);
    const calls = heldCallsOver(daemon, new PersonKey(null));
    expect(await calls.answer('hld_1', 'once')).toEqual({ kind: 'failed', why: NO_KEY_LINE });
    expect(daemon.sent('confirm')).toEqual([]);
  });

  it('reports the answer that came first rather than its own', async () => {
    const daemon = new ScriptedDaemon({
      ...nothingWaits,
      'register-key': registered,
      confirm: (request) => [{ id: request.id, ok: true, outcome: 'already answered deny' }],
    });
    daemon.push(held('hld_1'));
    const calls = heldCallsOver(daemon, new PersonKey());
    await calls.watch();
    const outcome = await calls.answer('hld_1', 'once');
    expect(outcome.kind === 'answered-elsewhere' && outcome.earlier.line).toBe('That was already answered elsewhere: it was denied.');
    expect(calls.state.waiting.count).toBe(0);
  });

  it('says why the daemon would not take it and keeps the call', async () => {
    const daemon = new ScriptedDaemon({
      ...nothingWaits,
      'register-key': registered,
      confirm: (request) => [{ id: request.id, ok: false, error: 'signature does not verify' }],
    });
    daemon.push(held('hld_1'));
    const calls = heldCallsOver(daemon, new PersonKey());
    await calls.watch();
    expect(await calls.answer('hld_1', 'once')).toEqual({ kind: 'failed', why: 'signature does not verify' });
    expect(calls.state.waiting.count).toBe(1);
  });
});
