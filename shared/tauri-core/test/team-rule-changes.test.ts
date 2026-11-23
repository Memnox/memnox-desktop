import { describe, expect, it } from 'vitest';
import { CloudInbox } from '../src/core/application/cloud-inbox';
import type { HttpTransport, PersonCredentialStore } from '../src/core/application/ports/workspace-inbox';
import { WorkspaceAgents } from '../src/core/application/workspace-agents';
import { readCloudRuleChanges, teamRuleChangeLines, TeamRuleChangeLines } from '../src/core/domain/team-rule-changes';
import type { WorkspaceCredential } from '../src/core/domain/workspace-wire';

const credential: WorkspaceCredential = { token: 'tok', tokenId: 'tid', personId: 'psn_me', name: 'Bo', orgId: 'org_1', workspaces: ['ws_1'], deviceId: 'dev_1' };
const store: PersonCredentialStore = { load: async () => credential, save: async () => undefined, delete: async () => undefined };
const PROPOSALS = 'GET v1/workspaces/ws_1/policies/proposals?status=pending';

/** Memnox Cloud scripted by method and path. */
class Cloud implements HttpTransport {
  readonly asked: string[] = [];
  constructor(readonly routes: Record<string, { status: number; body: unknown }>) {}

  async send(method: 'GET' | 'POST' | 'DELETE', path: string) {
    this.asked.push(`${method} ${path}`);
    const route = this.routes[`${method} ${path}`];
    if (route === undefined) throw new Error(`no route for ${method} ${path}`);
    return { status: route.status, body: JSON.stringify(route.body) };
  }
}

const agents = { 'GET v1/workspaces/ws_1/agent-profiles': { status: 200, body: { profiles: [] } }, 'GET v1/workspaces/ws_1/me/agent-work': { status: 200, body: { work: [], handoffs: [] } } };

describe('team rule changes', () => {
  const now = Date.parse('2026-11-23T12:00:00Z');

  it('says what each changes and who asked in plain words', () => {
    const lines = teamRuleChangeLines(
      [
        { id: 'prp_1', proposedBy: 'Sam', proposedAt: '2026-11-23T10:00:00Z' },
        { id: 'prp_2', proposedBy: '', proposedAt: '2026-11-23T11:55:00Z', kind: 'shared_projects' },
      ],
      now,
    );
    expect(lines.map((each) => each.title)).toEqual(["A change to the team's rules", "A change to the team's projects"]);
    expect(lines.map((each) => each.caption)).toEqual([expect.stringMatching(/^Asked by Sam, /), expect.stringMatching(/^Asked by a teammate, /)]);
  });

  it('leaves out an item it cannot read rather than every other', () => {
    expect(readCloudRuleChanges([{ id: 'prp_1', proposedBy: 'Sam', proposedAt: 't' }, { id: 7 }]).map((each) => each.id)).toEqual(['prp_1']);
    expect(readCloudRuleChanges({ error: 'no' })).toEqual([]);
  });

  it("opens the console's rule changes list", () => {
    expect(TeamRuleChangeLines.consoleAddress).toBe('https://app.memnox.com/inbox?queue=rule-changes');
  });

  it('reads only the pending changes while signed in', async () => {
    const cloud = new Cloud({ ...agents, [PROPOSALS]: { status: 200, body: [{ id: 'prp_1', proposedBy: 'Sam', proposedAt: '2026-11-23T10:00:00Z', status: 'pending', kind: 'rules' }] } });
    const workspace = new WorkspaceAgents(new CloudInbox(cloud), store);
    await workspace.refresh();
    expect(workspace.remote[0]?.ruleChanges.map((each) => each.id)).toEqual(['prp_1']);
    expect(cloud.asked).toContain(PROPOSALS);
  });

  it('still shows the agents of a workspace that will not list its changes', async () => {
    const cloud = new Cloud({ ...agents, [PROPOSALS]: { status: 403, body: { message: 'Forbidden' } } });
    const workspace = new WorkspaceAgents(new CloudInbox(cloud), store);
    await workspace.refresh();
    expect(workspace.remote).toHaveLength(1);
    expect(workspace.remote[0]?.ruleChanges).toEqual([]);
  });
});
