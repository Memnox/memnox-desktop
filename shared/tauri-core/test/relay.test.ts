import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { HeldCalls } from '../src/core/application/held-calls';
import type { Paired, Pairer } from '../src/core/application/ports/pairer';
import { RequestIds } from '../src/core/application/request-ids';
import { ServerFeeds } from '../src/core/application/server-feeds';
import { ServerPairing } from '../src/core/application/server-pairing';
import { Signer } from '../src/core/application/signer';
import { Refused, TargetLink } from '../src/core/application/target-link';
import { Base64URL, fromBase64, utf8 } from '../src/core/domain/base64url';
import { callLabel, raisedOn } from '../src/core/domain/call-label';
import { heldCard } from '../src/core/domain/held-card';
import { deliversFrom } from '../src/core/domain/machine-events';
import { PairedMachines, type PairedServer } from '../src/core/domain/paired-machines';
import { readInvitation } from '../src/core/domain/pairing-invitation';
import { OWN_DEVICES, quietHere } from '../src/core/domain/quiet';
import { RESUBSCRIBE_MS, subscriptionEnd } from '../src/core/domain/relay/resubscribe';
import { isLastLine } from '../src/core/domain/relay/stream-end';
import { remoteAllows } from '../src/core/domain/remote-reach';
import { ServerPairingLines } from '../src/core/domain/server-pairing-lines';
import { held, PersonKey, registered, ScriptedDaemon } from './doubles';

const bytes = (length: number, fill: number) => new Uint8Array(length).fill(fill);
const standard = (data: Uint8Array) => Base64URL.encode(data).replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (Base64URL.encode(data).length % 4)) % 4);

function link(fields: Record<string, unknown> = {}): string {
  const wire = {
    v: 1,
    machineId: 'm_box',
    machine: 'build-box',
    relayUrl: 'wss://relay.memnox.com/v1/relay',
    mailbox: Base64URL.encode(bytes(16, 1)),
    pairingToken: 'rlp_1',
    runtimeNoiseStatic: standard(bytes(32, 2)),
    secret: standard(bytes(32, 3)),
    expiresAt: '2026-10-18T10:02:00.000Z',
    ...fields,
  };
  return `memnox://pair?d=${Base64URL.encode(new TextEncoder().encode(JSON.stringify(wire)))}`;
}

const NOW = Date.parse('2026-10-18T10:00:00.000Z');
const server = (machineId: string, pairedAt = 1, machine = machineId): PairedServer => ({ machineId, machine, deviceId: `dev_${machineId}`, pairedAt });

describe('base64', () => {
  it('round trips base64url without padding and reads standard base64 and UTF-8', () => {
    const data = Uint8Array.from([0, 250, 251, 252, 253, 254, 255]);
    expect(Base64URL.encode(data)).toBe('APr7_P3-_w');
    expect(Base64URL.decode('APr7_P3-_w')).toEqual(data);
    expect(fromBase64('APr7/P3+/w==')).toEqual(data);
    expect(Base64URL.decode('a+b')).toBeUndefined();
    expect(utf8(new TextEncoder().encode('Ana’s box'))).toBe('Ana’s box');
  });
});

describe('a pairing link', () => {
  it('reads the server it names', () => {
    expect(readInvitation(`  ${link()}\n`, NOW)).toEqual({ machineId: 'm_box', machine: 'build-box', relayUrl: 'wss://relay.memnox.com/v1/relay', expiresAt: NOW + 120_000 });
  });

  it('refuses what is not a link, unreadable, newer or ran out', () => {
    expect(readInvitation('https://example.com', NOW)).toEqual({ kind: 'not-a-pairing-link' });
    expect(readInvitation('memnox://pair?d=!!', NOW)).toEqual({ kind: 'unreadable' });
    expect(readInvitation(link({ mailbox: 'AAAA' }), NOW)).toEqual({ kind: 'unreadable' });
    expect(readInvitation(link({ v: 2 }), NOW)).toEqual({ kind: 'unsupported-version', version: 2 });
    expect(readInvitation(link(), NOW + 120_000)).toEqual({ kind: 'expired' });
  });
});

describe('the relay stream', () => {
  const id = 1;
  it('ends an ask on its last chunk, a speak on its last piece, and never a subscription', () => {
    expect(isLastLine({ id, ok: true, chunk: { kind: 'text', text: 'hi' } }, 'ask')).toBe(false);
    expect(isLastLine({ id, ok: true, chunk: { kind: 'done' } }, 'ask')).toBe(true);
    expect(isLastLine({ id, ok: false, error: 'no' }, 'ask')).toBe(true);
    expect(isLastLine({ id, ok: true, audio: { pcm: '', rate: 24_000, last: false } } as unknown as DaemonResponse, 'speak')).toBe(false);
    expect(isLastLine({ id, ok: true, event: held('a') }, 'subscribe')).toBe(false);
    expect(isLastLine({ id, ok: true }, 'ping')).toBe(true);
  });

  it('opens again at once after the hourly renewal and after a pause after a loss', () => {
    expect(RESUBSCRIBE_MS[subscriptionEnd(new Error('renewed'))]).toBe(0);
    expect(RESUBSCRIBE_MS[subscriptionEnd(new Error('disconnected'))]).toBe(5_000);
  });
});

describe('what reaches another machine', () => {
  it('sends only the remote allowlist, and a voice choice only when it asks', () => {
    expect(remoteAllows({ id: 1, method: 'ask' })).toBe(true);
    expect(remoteAllows({ id: 1, method: 'register-key' })).toBe(false);
    expect(remoteAllows({ id: 1, method: 'pair-begin' })).toBe(false);
    expect(remoteAllows({ id: 1, method: 'voice-choice' })).toBe(true);
    expect(remoteAllows({ id: 1, method: 'voice-choice', voice: 'af_heart' })).toBe(false);
  });

  it('brings from a machine not picked only what waits on the person', () => {
    expect(deliversFrom(held('a'), false, false)).toBe(true);
    expect(deliversFrom({ ...held('a'), kind: 'paused' }, false, false)).toBe(false);
    expect(deliversFrom({ ...held('a'), kind: 'paused' }, true, false)).toBe(true);
    expect(deliversFrom({ ...held('a'), kind: 'proposal' }, false, true)).toBe(true);
  });

  it('treats a stamp with this computer’s own device id as this computer speaking', () => {
    const event = { ...held('a'), origin: { deviceId: 'dev_box' } };
    expect(quietHere(event, false, new Set())).toBe(true);
    expect(quietHere(event, false, new Set(['dev_box']))).toBe(false);
    OWN_DEVICES.set([]);
  });
});

describe('a call on a server', () => {
  it('is labelled with the server and always signed', () => {
    expect(callLabel('Codex', raisedOn('build-box'))).toBe('Codex on build-box');
    expect(callLabel('Codex', raisedOn('  '))).toBe('Codex on this computer');
    expect(callLabel('Codex', { kind: 'team', machine: 'ci', person: 'Ana' })).toBe("Codex on ci, from Ana's team");
    expect(callLabel('Codex', { kind: 'team', machine: 'ci', person: undefined })).toBe('Codex on ci, from your team');
    const card = heldCard({ ...held('a'), agentName: 'Codex', withinSession: true }, raisedOn('build-box'));
    expect([card.who, card.label, card.withinSession, card.touchID]).toEqual(['Codex on build-box', 'Codex on build-box', false, true]);
  });

  it('is queued under the server and its signed yes goes back through the link it came from', async () => {
    const local = new ScriptedDaemon({ 'register-key': registered, confirm: (request) => [{ id: request.id, ok: true }] });
    const remote = new ScriptedDaemon({ confirm: (request) => [{ id: request.id, ok: true }] });
    const target = new TargetLink(local);
    target.register({ kind: 'server', machineId: 'm_box', deviceId: 'dev_box', name: 'build-box' }, remote);
    target.remember('apr_9', { kind: 'server', machineId: 'm_box', deviceId: 'dev_box', name: 'build-box' });
    const ids = new RequestIds();
    const key = new PersonKey();
    const calls = new HeldCalls(local, new Signer(local, key, ids), ids, { answers: target });
    calls.fromServer({ ...held('apr_9'), agentName: 'Codex', withinSession: true }, 'build-box');
    expect(calls.state.waiting.shown?.machine).toBe('build-box');
    expect(await calls.answer('apr_9', 'once')).toEqual({ kind: 'answered' });
    expect(local.sent('confirm')).toEqual([]);
    expect(remote.sent('confirm')[0]?.signature).toBe('sig(memnox-confirm:v1:apr_9:once)');
  });
});

describe('the target link', () => {
  const box = { kind: 'server' as const, machineId: 'm_box', deviceId: 'dev_box', name: 'build-box' };

  async function drain(lines: AsyncIterable<DaemonResponse>): Promise<DaemonResponse[]> {
    const all: DaemonResponse[] = [];
    for await (const line of lines) all.push(line);
    return all;
  }

  it('talks to the chosen server and keeps this computer’s own methods home', async () => {
    const local = new ScriptedDaemon({ ping: (request) => [{ id: request.id, ok: true, version: 'here' }] });
    const remote = new ScriptedDaemon({ ping: (request) => [{ id: request.id, ok: true, version: 'there' }] });
    const target = new TargetLink(local);
    target.choose(box);
    expect(target.isRemote).toBe(false);
    target.register(box, remote);
    target.choose(box);
    expect((await drain(target.stream({ id: 1, method: 'ping' })))[0]?.version).toBe('there');
    await expect(drain(target.stream({ id: 2, method: 'register-key' }))).rejects.toBeInstanceOf(Refused);
    target.unregister('m_box');
    expect(target.target.kind).toBe('this-computer');
    expect((await drain(target.stream({ id: 3, method: 'ping' })))[0]?.version).toBe('here');
  });

  it('never sends a workspace call to a daemon', async () => {
    const target = new TargetLink(new ScriptedDaemon());
    target.rememberWorkspace('hc_1');
    await expect(drain(target.stream({ id: 1, method: 'confirm', subject: 'hc_1' }))).rejects.toBeInstanceOf(Refused);
  });

  it('ends a stream that followed the choice when the choice changes', async () => {
    let release: () => void = () => undefined;
    const forever: DaemonLinkLike = {
      async *stream(request: DaemonRequest) {
        yield { id: request.id, ok: true };
        await new Promise<void>((resolve) => {
          release = resolve;
        });
      },
    };
    const target = new TargetLink(forever);
    const lines = drain(target.stream({ id: 1, method: 'subscribe' }));
    await Promise.resolve();
    target.register(box, new ScriptedDaemon());
    target.choose(box);
    expect(await lines).toHaveLength(1);
    release();
  });
});

type DaemonLinkLike = { stream(request: DaemonRequest): AsyncIterable<DaemonResponse> };

describe('the servers kept', () => {
  it('keeps the newest pairing of each machine, oldest first', () => {
    expect(PairedMachines.distinct([server('b', 2), server('a', 1), server('b', 3)]).map((each) => [each.machineId, each.pairedAt])).toEqual([
      ['a', 1],
      ['b', 3],
    ]);
  });

  it('listens to every server, routes their calls back and drops one forgotten', async () => {
    const feeds: ScriptedDaemon[] = [];
    const target = new TargetLink(new ScriptedDaemon());
    const delivered: [string, string][] = [];
    const watcher = new ServerFeeds(
      target,
      () => {
        const daemon = new ScriptedDaemon();
        daemon.push(held('apr_1'));
        feeds.push(daemon);
        return daemon;
      },
      new RequestIds(),
      (event: DaemonEvent, name) => delivered.push([event.subject, name]),
      () => new Promise(() => undefined),
    );
    watcher.restore([server('m_box', 1, 'build-box')], 'm_box');
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(delivered).toEqual([['apr_1', 'build-box']]);
    expect(target.serverNameFor('apr_1')).toBe('build-box');
    expect(target.target).toEqual({ kind: 'server', machineId: 'm_box', deviceId: 'dev_m_box', name: 'build-box' });
    expect(OWN_DEVICES.ids.has('dev_m_box')).toBe(true);
    watcher.restore([], undefined);
    expect(target.target.kind).toBe('this-computer');
    expect(target.serverNameFor('apr_1')).toBeUndefined();
    OWN_DEVICES.set([]);
  });
});

describe('connecting to a server', () => {
  function pairer(result: Paired, digits = '482913'): Pairer & { kept: PairedServer[] } {
    const kept: PairedServer[] = [];
    return {
      kept,
      async pair(_link, _name, code) {
        code(digits);
        if (result.kind === 'paired') kept.push(result.server);
        return result;
      },
      servers: async () => kept,
      forget: async (machineId) => void kept.splice(kept.findIndex((each) => each.machineId === machineId), 1),
    };
  }

  it('shows the digits to type there, then says it connected and keeps the server', async () => {
    const steps: string[] = [];
    let changed = 0;
    const fake = pairer({ kind: 'paired', server: server('m_box', 1, 'build-box') });
    const pairing = new ServerPairing(fake, () => 'Desk', 'Windows Hello', () => (changed += 1), () => NOW);
    pairing.observe(() => steps.push(pairing.step.kind === 'showing-code' ? `code ${pairing.step.code}` : pairing.step.kind));
    await pairing.connect(link());
    expect(steps).toContain('code 482913');
    expect(pairing.step).toEqual({ kind: 'connected', name: 'build-box' });
    expect(pairing.servers.map((each) => each.machineId)).toEqual(['m_box']);
    expect(changed).toBe(1);
    await pairing.forget('m_box');
    expect(pairing.servers).toEqual([]);
  });

  it('refuses a link that ran out before reaching the relay, and says why a pairing failed', async () => {
    const fake = pairer({ kind: 'failed', why: { kind: 'cancelled' } });
    const pairing = new ServerPairing(fake, () => 'Desk', 'Windows Hello', undefined, () => NOW + 200_000);
    await pairing.connect(link());
    expect(pairing.step).toEqual({ kind: 'failed', why: ServerPairingLines.failed({ kind: 'expired' }, 'Windows Hello') });
    const later = new ServerPairing(fake, () => 'Desk', 'Windows Hello', undefined, () => NOW);
    await later.connect(link());
    expect(later.step).toEqual({ kind: 'failed', why: 'Windows Hello was cancelled, so this computer did not pair.' });
  });
});
