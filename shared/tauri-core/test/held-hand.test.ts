import { describe, expect, it } from 'vitest';
import { handedOutcome, type HeldCalls } from '../src/core/application/held-calls';
import { EarlierAnswer } from '../src/core/domain/earlier-answer';
import { HandTimer, held, heldCallsOver, PersonKey, ScriptedDaemon } from './doubles';

/**
 * A page's answer handed to the island, as the Mac's Approvals and Today hand theirs: the window holds the call as
 * pressed while the island signs it, and settles its own card from the island's word.
 */
const nothingWaits = { waiting: (request: { id: number }) => [{ id: request.id, ok: true, waiting: [] }] };

async function waitingOn(...subjects: string[]): Promise<{ calls: HeldCalls; timer: HandTimer; daemon: ScriptedDaemon }> {
  const daemon = new ScriptedDaemon(nothingWaits);
  for (const subject of subjects) daemon.push(held(subject));
  const timer = new HandTimer();
  const calls = heldCallsOver(daemon, new PersonKey(), timer);
  await calls.watch();
  return { calls, timer, daemon };
}

describe('a held call answered through the island', () => {
  it('holds the call as pressed and the allows dimmed while the island signs it', async () => {
    const { calls } = await waitingOn('hld_1');
    calls.handed('hld_1', 'once');
    expect(calls.state).toMatchObject({ answering: true, pressed: 'hld_1' });
  });

  it('dims nothing for a deny, which needs no key, as the Mac sets answering only for a yes', async () => {
    const { calls } = await waitingOn('hld_1');
    calls.handed('hld_1', 'deny');
    expect(calls.state).toMatchObject({ answering: false, pressed: 'hld_1' });
  });

  it('takes the card off at once when the answer stood, with no note of its own', async () => {
    const { calls } = await waitingOn('hld_1');
    calls.handed('hld_1', 'once');
    calls.handedBack('hld_1', { kind: 'answered' });
    expect(calls.state.waiting.count).toBe(0);
    expect(calls.state).toMatchObject({ answering: false, pressed: undefined, settled: undefined });
  });

  it('lets the card go at once when the feed says it settled before the island answers', async () => {
    const { calls } = await waitingOn('hld_1');
    calls.handed('hld_1', 'once');
    calls.handle({ ...held('hld_1'), kind: 'settled' });
    expect(calls.state.waiting.count).toBe(0);
    expect(calls.state).toMatchObject({ answering: false, settled: undefined });
    calls.handedBack('hld_1', { kind: 'answered' });
    expect(calls.state.answering).toBe(false);
  });

  it('says who got there first for a moment before the card goes, as the island card does', async () => {
    const { calls, timer } = await waitingOn('hld_1');
    calls.handed('hld_1', 'once');
    calls.handedBack('hld_1', { kind: 'answered-elsewhere', word: 'deny' });
    expect(calls.state.settled).toEqual({ subject: 'hld_1', note: 'Denied elsewhere' });
    timer.fireAll();
    expect(calls.state.waiting.count).toBe(0);
  });

  it('keeps the call and its answers once more when the key was put away or the answer failed', async () => {
    const { calls } = await waitingOn('hld_1');
    calls.handed('hld_1', 'once');
    calls.handedBack('hld_1', { kind: 'cancelled' });
    expect(calls.state.waiting.count).toBe(1);
    expect(calls.state).toMatchObject({ answering: false, pressed: undefined });
    calls.handed('hld_1', 'session');
    calls.handedBack('hld_1', { kind: 'failed', why: 'signature does not verify' });
    expect(calls.state.waiting.count).toBe(1);
    expect(calls.state.answering).toBe(false);
  });
});

describe('the island telling a page how it ended', () => {
  it('hands every outcome back as plain data, carrying only the word of an earlier answer', () => {
    expect(handedOutcome({ kind: 'answered' })).toEqual({ kind: 'answered' });
    expect(handedOutcome({ kind: 'cancelled' })).toEqual({ kind: 'cancelled' });
    expect(handedOutcome({ kind: 'failed', why: 'no' })).toEqual({ kind: 'failed', why: 'no' });
    const earlier = EarlierAnswer.from({ id: 1, ok: true, outcome: 'already answered deny' });
    expect(earlier && handedOutcome({ kind: 'answered-elsewhere', earlier })).toEqual({ kind: 'answered-elsewhere', word: 'deny' });
    expect(handedOutcome({ kind: 'answered-elsewhere', earlier: EarlierAnswer.unknown() })).toEqual({ kind: 'answered-elsewhere' });
  });
});
