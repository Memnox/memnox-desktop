import type { DaemonEvent } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { CloudInbox } from '../src/core/application/cloud-inbox';
import { HeldCalls } from '../src/core/application/held-calls';
import type { HttpTransport, PersonCredentialStore } from '../src/core/application/ports/workspace-inbox';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking } from '../src/core/application/talking';
import { TeamInbox } from '../src/core/application/team-inbox';
import { WorkspaceAnswering } from '../src/core/application/workspace-answering';
import { WorkspaceSignIn } from '../src/core/application/workspace-sign-in';
import { teamHeldCard } from '../src/core/domain/held-card';
import { teamQuestion } from '../src/core/domain/team-question';
import { WorkspaceLines } from '../src/core/domain/workspace-lines';
import { readHeldCall, type WorkspaceCredential } from '../src/core/domain/workspace-wire';
import { HandTimer, held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

type Route = (body: Record<string, string> | undefined, token: string | undefined) => { status: number; body: unknown };

/** Memnox Cloud scripted by method and path, every exchange kept. */
class Cloud implements HttpTransport {
  readonly sent: { method: string; path: string; body: Record<string, string> | undefined; token: string | undefined }[] = [];
  constructor(readonly routes: Record<string, Route>) {}

  async send(method: 'GET' | 'POST' | 'DELETE', path: string, body: string | undefined, token: string | undefined) {
    const parsed = body === undefined ? undefined : (JSON.parse(body) as Record<string, string>);
    this.sent.push({ method, path, body: parsed, token });
    const route = this.routes[`${method} ${path}`];
    if (route === undefined) throw new Error(`no route for ${method} ${path}`);
    const answer = route(parsed, token);
    return { status: answer.status, body: JSON.stringify(answer.body) };
  }
}

class MemoryCredential implements PersonCredentialStore {
  constructor(public kept: WorkspaceCredential | undefined = undefined, private readonly refuses = false) {}
  async load() {
    return this.kept;
  }
  async save(credential: WorkspaceCredential) {
    if (this.refuses) throw new Error('locked');
    this.kept = credential;
  }
  async delete() {
    this.kept = undefined;
  }
}

const credential: WorkspaceCredential = { token: 'tok', tokenId: 'tk_1', personId: 'p_1', name: 'Sam', orgId: 'o_1', workspaces: ['ws_1'], deviceId: 'dev_1' };
const call = (id: string, extra: Record<string, unknown> = {}) => ({ id, machineId: 'm_ci', machineLabel: 'ci', agent: 'Codex', operation: 'git push', target: 'origin main', reason: 'push to main', askedAt: `2026-10-18T10:00:0${id.slice(-1)}.000Z`, expiresAt: '2099-01-01T00:00:00.000Z', ownerName: 'Ana', ...extra });
const HELD = 'GET v1/workspaces/ws_1/me/held?include=recent';

describe('a teammate’s call', () => {
  it('reads leniently, is labelled with the machine and the team, and is said as a question', () => {
    const read = readHeldCall(call('hc_1'));
    expect(readHeldCall({ machineId: 'm' })).toBeUndefined();
    if (read === undefined) throw new Error('unread');
    expect(teamHeldCard(read)).toMatchObject({ subject: 'hc_1', who: "Codex on ci, from Ana's team", what: 'git push origin main', why: 'push to main', touchID: true, withinSession: false });
    expect(teamQuestion('Sam', read)).toBe("Sam, Codex on ci, from Ana's team is waiting on you. git push origin main. push to main. Allow it, or deny?");
  });
});

describe('signing in to the workspace', () => {
  const routes = (): Record<string, Route> => ({
    'POST v1/person/codes': () => ({ status: 200, body: { deviceCode: 'dc', userCode: 'WDJB-MJHT', intervalSeconds: 5, expiresAt: 10_000_000 } }),
    'POST v1/person/tokens': () => ({ status: 200, body: { token: 'tok', tokenId: 'tk_1', personId: 'p_1', name: 'Sam', role: 'member', orgId: 'o_1' } }),
    'GET v1/me': () => ({ status: 200, body: { workspaces: [{ id: 'ws_1', orgId: 'o_1' }, { id: 'ws_other', orgId: 'o_2' }] } }),
    'POST v1/me/devices': (body) => ({ status: 200, body: { id: 'dev_1', name: body?.['name'] } }),
    'DELETE v1/me/devices/dev_1': () => ({ status: 204, body: {} }),
  });

  it('shows the code, registers the key and keeps the credential for the organisation that granted it', async () => {
    const cloud = new Cloud(routes());
    const store = new MemoryCredential();
    const codes: string[] = [];
    const signIn = new WorkspaceSignIn(new CloudInbox(cloud), store, new PersonKey(), async () => undefined, () => 1_000);
    const outcome = await signIn.signIn('Desk', (code) => codes.push(code.userCode));
    expect(codes).toEqual(['WDJB-MJHT']);
    expect(outcome).toEqual({ kind: 'signed-in', credential });
    expect(cloud.sent.find((each) => each.path === 'v1/me/devices')?.body).toEqual({ kind: 'desktop', name: 'Desk', signingPoint: 'BPOINT' });
    await signIn.signOut();
    expect(store.kept).toBeUndefined();
  });

  it('asks again while the console has not answered, and says a refusal plainly', async () => {
    let asked = 0;
    const cloud = new Cloud({ ...routes(), 'POST v1/person/tokens': () => (++asked < 3 ? { status: 400, body: { error: 'authorization_pending' } } : { status: 400, body: { error: 'access_denied' } }) });
    const signIn = new WorkspaceSignIn(new CloudInbox(cloud), new MemoryCredential(), new PersonKey(), async () => undefined, () => 1_000);
    expect(await signIn.signIn('Desk', () => undefined)).toEqual({ kind: 'stopped', why: 'The sign in was declined in the console.' });
    expect(asked).toBe(3);
  });

  it('refuses with no key, and removes the device again when the credential cannot be kept', async () => {
    const none = new WorkspaceSignIn(new CloudInbox(new Cloud(routes())), new MemoryCredential(), new PersonKey(null), async () => undefined);
    expect(await none.signIn('Desk', () => undefined)).toEqual({ kind: 'stopped', why: WorkspaceLines.noKey });
    const cloud = new Cloud(routes());
    const locked = new WorkspaceSignIn(new CloudInbox(cloud), new MemoryCredential(undefined, true), new PersonKey(), async () => undefined, () => 1_000);
    expect(await locked.signIn('Desk', () => undefined)).toEqual({ kind: 'stopped', why: WorkspaceLines.notKept });
    expect(cloud.sent.at(-1)).toMatchObject({ method: 'DELETE', path: 'v1/me/devices/dev_1' });
  });
});

describe('the workspace inbox', () => {
  function inbox(listed: () => unknown[], answer: Route = () => ({ status: 200, body: { id: 'hc_1', status: 'answered', approvalsNeeded: 1 } })) {
    const cloud = new Cloud({ [HELD]: () => ({ status: 200, body: listed() }), 'POST v1/workspaces/ws_1/me/held/hc_1': answer });
    const key = new PersonKey();
    const answering = new WorkspaceAnswering(new CloudInbox(cloud), new MemoryCredential(credential), key, () => Date.parse('2026-10-18T11:00:00.000Z'));
    return { cloud, key, answering };
  }

  it('says what arrived and what went, with who answered it elsewhere', async () => {
    let listed: unknown[] = [call('hc_1'), call('hc_2', { approvedByYou: true }), call('hc_3', { expiresAt: '2026-10-18T10:30:00.000Z' })];
    const { answering } = inbox(() => listed);
    const first = await answering.refresh();
    expect(first.arrived.map((each) => each.id)).toEqual(['hc_1']);
    expect(answering.briefs()).toEqual([{ id: 'hc_1', label: "Codex on ci, from Ana's team", what: 'git push origin main' }]);
    listed = [call('hc_1', { answer: 'once', answeredBy: 'Ana', answeredOn: 'console' })];
    const second = await answering.refresh();
    expect(second.gone).toEqual(['hc_1']);
    expect(second.answeredElsewhere.get('hc_1')).toBe('Allowed once by Ana in the console');
  });

  it('signs a yes over exactly that call and sends a deny unsigned', async () => {
    const { answering, cloud, key } = inbox(() => [call('hc_1')]);
    await answering.refresh();
    expect(await answering.answer('hc_1', 'once', 'allow it once')).toEqual({ kind: 'answered' });
    expect(key.signed.map((each) => each.message)).toEqual(['memnox-confirm:v1:hc_1:once']);
    expect(cloud.sent.at(-1)?.body).toEqual({ answer: 'once', deviceId: 'dev_1', signature: 'sig(memnox-confirm:v1:hc_1:once)' });
    expect(answering.owns('hc_1')).toBe(false);
    const again = inbox(() => [call('hc_1')]);
    await again.answering.refresh();
    await again.answering.answer('hc_1', 'deny', 'deny it');
    expect(again.key.signed).toEqual([]);
    expect(again.cloud.sent.at(-1)?.body).toEqual({ answer: 'deny', deviceId: 'dev_1' });
  });

  it('reads a conflict as answered elsewhere and a refused signature in plain words', async () => {
    const settled = inbox(() => [call('hc_1')], () => ({ status: 409, body: { message: 'already answered' } }));
    await settled.answering.refresh();
    expect((await settled.answering.answer('hc_1', 'once', 'r')).kind).toBe('answered-elsewhere');
    const refused = inbox(() => [call('hc_1')], () => ({ status: 403, body: { message: 'bad signature' } }));
    await refused.answering.refresh();
    expect(await refused.answering.answer('hc_1', 'once', 'r')).toEqual({ kind: 'failed', why: WorkspaceLines.notReached });
  });

  it('is read on a timer and again at once after the computer slept, and a revoked sign in is forgotten', async () => {
    let status = 200;
    const cloud = new Cloud({ [HELD]: () => ({ status, body: status === 200 ? [call('hc_1')] : { message: 'revoked' } }) });
    const store = new MemoryCredential(credential);
    const answering = new WorkspaceAnswering(new CloudInbox(cloud), store, new PersonKey());
    const timer = new HandTimer();
    let clock = 0;
    const seen: string[] = [];
    const team = new TeamInbox(answering, { arrived: (each) => seen.push(`arrived ${each.id}`), gone: (id, note) => seen.push(`gone ${id} ${String(note)}`), signedOut: () => seen.push('signed out') }, timer.start, () => clock);
    team.start();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(seen).toEqual(['arrived hc_1']);
    status = 401;
    clock = 60_000;
    timer.fireAll();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(seen).toEqual(['arrived hc_1', 'signed out', 'gone hc_1 undefined']);
    team.stop();
  });
});

describe('a teammate’s call on the island and by voice', () => {
  async function island() {
    const daemon = new ScriptedDaemon({ 'register-key': registered, confirm: (request) => [{ id: request.id, ok: true }], ask: (request) => [{ id: request.id, ok: true, chunk: { kind: 'done' } }] });
    const cloud = new Cloud({ [HELD]: () => ({ status: 200, body: [call('hc_1')] }), 'POST v1/workspaces/ws_1/me/held/hc_1': () => ({ status: 200, body: { id: 'hc_1', status: 'answered', approvalsNeeded: 1 } }) });
    const key = new PersonKey();
    const answering = new WorkspaceAnswering(new CloudInbox(cloud), new MemoryCredential(credential), key);
    await answering.refresh();
    const ids = new RequestIds();
    const signer = new Signer(daemon, key, ids);
    const calls = new HeldCalls(daemon, signer, ids, { team: answering });
    const speaker = new RecordingSpeaker();
    const answered: string[] = [];
    const talking = new Talking(daemon, speaker, signer, ids, { timer: new HandTimer().start, team: answering, teamAnswered: (subject) => answered.push(subject) });
    return { daemon, cloud, key, answering, calls, speaker, talking, answered };
  }

  it('is answered from its card through the workspace and never a daemon', async () => {
    const { calls, cloud, daemon, answering } = await island();
    const read = answering.call('hc_1');
    if (read === undefined) throw new Error('no call');
    calls.holdTeam(read);
    expect(calls.state.waiting.shown?.machine).toBe('ci');
    expect(await calls.answer('hc_1', 'always')).toEqual({ kind: 'answered' });
    expect(daemon.sent('confirm')).toEqual([]);
    expect(cloud.sent.at(-1)?.body?.['answer']).toBe('once');
    expect(calls.state.waiting.count).toBe(0);
  });

  it('is announced, named on every ask, and carried out by voice with both signatures', async () => {
    const { talking, speaker, daemon, cloud, key, answering, answered } = await island();
    const read = answering.call('hc_1');
    if (read === undefined) throw new Error('no call');
    await talking.announceTeam(read);
    expect(speaker.said.at(-1)).toContain('is waiting on you.');
    await talking.heard('allow it for Ana');
    expect(daemon.sent('ask')[0]?.teamCalls).toEqual([{ id: 'hc_1', label: "Codex on ci, from Ana's team", what: 'git push origin main' }]);
    const proposal: DaemonEvent = { ...held('prp_1'), kind: 'proposal', summary: 'answer Ana', teamAnswer: { callId: 'hc_1', answer: 'once', label: 'x' } };
    await talking.handle(proposal);
    expect(key.signed.map((each) => each.message)).toEqual(['memnox-confirm:v1:hc_1:once', 'memnox-confirm:v1:prp_1:confirmed']);
    expect(cloud.sent.at(-1)?.body?.['signature']).toBe('sig(memnox-confirm:v1:hc_1:once)');
    expect(daemon.sent('confirm').map((each) => [each.subject, each.answer, each.signature])).toEqual([['prp_1', 'confirmed', 'sig(memnox-confirm:v1:prp_1:confirmed)']]);
    expect(answered).toEqual(['hc_1']);
    expect(speaker.said.at(-1)).toBe(WorkspaceLines.answeredByVoice);
  });
});
