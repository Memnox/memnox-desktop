import { describe, expect, it } from 'vitest';
import { CloudInbox } from '../src/core/application/cloud-inbox';
import type { HttpTransport, PersonCredentialStore } from '../src/core/application/ports/workspace-inbox';
import { WorkspaceAgents } from '../src/core/application/workspace-agents';
import { levelRows, seamRows } from '../src/core/domain/capability-level-lines';
import { cloudLevels, cloudProfileView, cloudWorkAll, responsibleOf, waitingHandoffs, type CloudProfileView } from '../src/core/domain/workspace-agents';
import type { WorkspaceCredential } from '../src/core/domain/workspace-wire';

const credential: WorkspaceCredential = { token: 'tok', tokenId: 'tid', personId: 'psn_me', name: 'Bo', orgId: 'org_1', workspaces: ['ws_1'], deviceId: 'dev_1' };

/** Memnox Cloud scripted by method and path, every exchange kept. */
class Cloud implements HttpTransport {
  readonly sent: { method: string; path: string; body: unknown }[] = [];
  constructor(readonly routes: Record<string, { status: number; body: unknown }>) {}

  async send(method: 'GET' | 'POST' | 'DELETE', path: string, body: string | undefined) {
    this.sent.push({ method, path, body: body === undefined ? undefined : JSON.parse(body) });
    const route = this.routes[`${method} ${path}`];
    if (route === undefined) throw new Error(`no route for ${method} ${path}`);
    return { status: route.status, body: JSON.stringify(route.body) };
  }
}

const store = (kept: WorkspaceCredential | undefined): PersonCredentialStore => ({ load: async () => kept, save: async () => undefined, delete: async () => undefined });

const hosted: CloudProfileView = {
  profile: { id: 'prf_1', name: 'Content Agent', purpose: 'Drafts the campaign briefs', responsiblePersonId: 'psn_me', projects: [] },
  connected: true,
  connections: [{ machineId: 'mch_1', connection: 'gateway', label: 'openai', live: true, levels: { context: 'mediated', enforcement: 'observed' } }],
  levels: { context: 'mediated', instructions: 'advisory', tools: 'mediated', activity: 'observed', coordination: 'none', approval: 'mediated', enforcement: 'observed' },
};

const mine = {
  work: [{ id: 'wrk_1', agentProfileId: 'prf_1', responsiblePersonId: 'psn_me', target: { source: 'linear', externalId: 'LIN-9', url: 'https://linear.app/x/LIN-9' }, status: 'handoff_requested', createdAt: 't', updatedAt: 't' }],
  handoffs: [
    { id: 'hof_1', workId: 'wrk_1', fromProfileId: 'prf_1', toProfileId: 'prf_2', reason: 'needs numbers', state: 'requested', requestedAt: 't' },
    { id: 'hof_2', workId: 'wrk_other', fromProfileId: 'prf_3', toPersonId: 'psn_me', reason: 'over to you', state: 'requested', requestedAt: 't' },
  ],
};

describe('the workspace’s agents, as Memnox Cloud sends them', () => {
  it('names who answers by the name the cloud sends, else you or a teammate, else nobody', () => {
    expect(responsibleOf({ profile: { id: 'p', name: 'p', responsiblePersonId: 'psn_me', responsiblePersonName: 'Bo Diaz' } }, 'psn_me')).toBe('Bo Diaz');
    expect(responsibleOf({ profile: { id: 'p', name: 'p', responsiblePersonId: 'psn_x' }, responsiblePersonName: 'Ana' }, 'psn_me')).toBe('Ana');
    expect(responsibleOf({ profile: { id: 'p', name: 'p', responsiblePersonId: 'psn_me' } }, 'psn_me')).toBe('you');
    expect(responsibleOf({ profile: { id: 'p', name: 'p', responsiblePersonId: 'psn_x' } }, 'psn_me')).toBe('a teammate');
    expect(responsibleOf({ profile: { id: 'p', name: 'p', responsiblePersonId: 'psn_x', responsiblePersonName: 'Ana' }, needsResponsiblePerson: true }, 'psn_me')).toBeUndefined();
  });

  it('draws a hosted agent with the cloud’s levels only, enforcement as one seam and anything unsaid outside Memnox', () => {
    const view = cloudProfileView(hosted, 'psn_me');
    expect(view.responsiblePerson).toBe('you');
    expect(view.connections[0]).toMatchObject({ kind: 'gateway', agentKind: 'openai', status: 'live' });
    expect(levelRows(view.connections[0]?.levels ?? cloudLevels(undefined)).find((row) => row.key === 'tools')?.plain).toBe('Outside Memnox');
    expect(seamRows(view.levels).map((row) => [row.title, row.plain])).toEqual([['Everything it runs', 'Memnox only sees this']]);
    expect(cloudLevels({ context: 'claimed' }).context).toBe('none');
  });

  it('joins handoffs to their work, and gives one on work the person does not answer for a piece of its own', () => {
    const work = cloudWorkAll(mine);
    expect(work.map((each) => each.id)).toEqual(['wrk_1', 'wrk_other']);
    expect(work[0]?.handoffs.map((each) => each.id)).toEqual(['hof_1']);
    expect(work[1]?.handoffs[0]?.to.person).toBe('psn_me');
    expect(waitingHandoffs([{ workspace: 'ws_1', work }]).map((each) => each.handoff.id)).toEqual(['hof_1', 'hof_2']);
  });
});

describe('reading the workspace’s agents', () => {
  it('sends nothing with no account, and holds nothing', async () => {
    const cloud = new Cloud({});
    const agents = new WorkspaceAgents(new CloudInbox(cloud), store(undefined));
    await agents.refresh();
    expect(agents.signedIn).toBe(false);
    expect(agents.remote).toEqual([]);
    expect(cloud.sent).toEqual([]);
    expect(await agents.answer('hof_1', 'ws_1', 'accept')).toEqual({ kind: 'failed', why: 'Sign in to Memnox Cloud to answer this.' });
  });

  it('reads each workspace’s jobs and work, dropping an entry it cannot read', async () => {
    const cloud = new Cloud({
      'GET v1/workspaces/ws_1/agent-profiles': { status: 200, body: { profiles: [hosted, { profile: { name: 'no id' } }] } },
      'GET v1/workspaces/ws_1/me/agent-work': { status: 200, body: mine },
    });
    const agents = new WorkspaceAgents(new CloudInbox(cloud), store(credential));
    await agents.refresh();
    expect(agents.signedIn).toBe(true);
    expect(agents.remote[0]?.profiles.map((each) => each.name)).toEqual(['Content Agent']);
    expect(agents.remote[0]?.work).toHaveLength(2);
  });

  it('keeps what a workspace showed when it does not answer, and forgets all of it once signed out', async () => {
    const routes: Record<string, { status: number; body: unknown }> = {
      'GET v1/workspaces/ws_1/agent-profiles': { status: 200, body: { profiles: [hosted] } },
      'GET v1/workspaces/ws_1/me/agent-work': { status: 200, body: mine },
    };
    const cloud = new Cloud(routes);
    const agents = new WorkspaceAgents(new CloudInbox(cloud), store(credential));
    await agents.refresh();
    routes['GET v1/workspaces/ws_1/agent-profiles'] = { status: 500, body: { message: 'down' } };
    await agents.refresh();
    expect(agents.remote[0]?.profiles).toHaveLength(1);
    routes['GET v1/workspaces/ws_1/agent-profiles'] = { status: 401, body: {} };
    await agents.refresh();
    expect(agents.signedIn).toBe(false);
    expect(agents.remote).toEqual([]);
  });

  it('answers a handoff unsigned with the cloud’s own boolean, and says a refusal in the cloud’s words', async () => {
    const routes: Record<string, { status: number; body: unknown }> = {
      'POST v1/workspaces/ws_1/me/handoffs/hof_1/answer': { status: 200, body: {} },
      'GET v1/workspaces/ws_1/agent-profiles': { status: 200, body: { profiles: [] } },
      'GET v1/workspaces/ws_1/me/agent-work': { status: 200, body: { work: [], handoffs: [] } },
    };
    const cloud = new Cloud(routes);
    const agents = new WorkspaceAgents(new CloudInbox(cloud), store(credential));
    expect(await agents.answer('hof_1', 'ws_1', 'decline')).toEqual({ kind: 'done', note: 'Declined. The work stays with the agent that has it.' });
    expect(cloud.sent[0]).toEqual({ method: 'POST', path: 'v1/workspaces/ws_1/me/handoffs/hof_1/answer', body: { accept: false } });
    routes['POST v1/workspaces/ws_1/me/handoffs/hof_1/answer'] = { status: 409, body: { message: 'Already answered.' } };
    expect(await agents.answer('hof_1', 'ws_1', 'accept')).toEqual({ kind: 'failed', why: 'Already answered.' });
    expect(agents.busy).toBeUndefined();
  });
});
