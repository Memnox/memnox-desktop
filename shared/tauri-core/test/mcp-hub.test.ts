import type { DaemonRequest, McpHubView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { McpHub, syncedLine } from '../src/core/application/mcp-hub';
import { RequestIds } from '../src/core/application/request-ids';
import { fromOrganization, GIVE_EVERYWHERE, headerLines, headerProblem, headerReference, headersOf, headerSecretName, isCredentialHeader, remoteAddressProblem, PROJECT_ONLY_LINE, missingSecrets, projectFolder, projectHelp, projectOnlyHelp, pressLine, projectsFor, reachCaption, reachOf, secretsAcross, serverNameFrom, splitCommand, transportWord, usedBy } from '../src/core/domain/mcp-hub-lines';
import { ScriptedDaemon } from './doubles';

const view: McpHubView = {
  servers: [
    {
      name: 'github',
      transport: 'stdio',
      command: 'npx',
      args: ['-y', 'server-github'],
      envNames: [],
      scope: 'personal',
      governed: true,
      toolCount: 3,
      health: { state: 'unknown' },
      agents: ['claude-code'],
      secretsHeld: { 'github-token': true },
      callsThisWeek: 4,
    },
  ],
  agents: [{ agent: 'claude-code', path: '/home/me/.claude.json' }],
  found: [{ agent: 'cursor', path: '/home/me/.cursor/mcp.json', name: 'notion' }],
  drifted: [],
  skipped: [],
};

describe('the MCP Hub as the window keeps it', () => {
  it('reads the hub and redraws from every answer', async () => {
    const daemon = new ScriptedDaemon({ 'mcp-hub': (request) => [{ id: request.id, ok: true, mcpHub: view }] });
    const hub = new McpHub(daemon, new RequestIds());
    await hub.refresh();
    expect(hub.hub?.servers[0]?.name).toBe('github');
    expect(hub.unreadable).toBe(false);
  });

  it('says a widening change waits for a signature rather than claiming it is done', async () => {
    const daemon = new ScriptedDaemon({ 'mcp-assign': (request) => [{ id: request.id, ok: true, proposed: 'prp_1' }] });
    const hub = new McpHub(daemon, new RequestIds());
    expect(await hub.assign('github', 'codex-cli', true)).toEqual({ kind: 'proposed', id: 'prp_1' });
    expect(daemon.sent('mcp-assign')[0]).toMatchObject({ mcpServerName: 'github', mcpAgent: 'codex-cli', mcpOn: true });
  });

  it('passes on the runtime’s refusal in its own words', async () => {
    const daemon = new ScriptedDaemon({ 'mcp-secret-set': (request: DaemonRequest) => [{ id: request.id, ok: false, error: 'only on this computer' }] });
    const hub = new McpHub(daemon, new RequestIds());
    expect(await hub.setSecret('github-token', 'value')).toEqual({ kind: 'failed', why: 'only on this computer' });
  });

  it('says what a sync wrote, or that nothing needed writing', () => {
    expect(syncedLine({ added: 1, updated: 0, removed: 2, files: ['a', 'b'] })).toBe('Wrote 2 configs: 1 added, 2 removed.');
    expect(syncedLine({ added: 0, updated: 0, removed: 0, files: [] })).toBe('Every agent already has what the hub gives it.');
  });
});

describe('the hub’s words', () => {
  it('lists each secret once with every server that needs it', () => {
    const across = secretsAcross([
      { name: 'github', secretsHeld: { token: true } },
      { name: 'gh-enterprise', secretsHeld: { token: false, other: true } },
    ]);
    expect(across).toEqual([
      { name: 'other', held: true, usedBy: ['gh-enterprise'] },
      { name: 'token', held: false, usedBy: ['github', 'gh-enterprise'] },
    ]);
    expect(missingSecrets({ secretsHeld: { a: true, b: false } })).toEqual(['b']);
  });

  it('turns what a person typed into a name and a launch line', () => {
    expect(serverNameFrom('  My GitHub! ')).toBe('my-github-');
    expect(splitCommand('npx -y "@scope/server name" --flag')).toEqual({ command: 'npx', args: ['-y', '@scope/server name', '--flag'] });
    expect(splitCommand('   ')).toBeUndefined();
  });
});

describe('a server added with agents chosen', () => {
  it('gives it to them only once the signed server is in the hub', async () => {
    let signed = false;
    const daemon = new ScriptedDaemon({
      'mcp-hub': (request) => [{ id: request.id, ok: true, mcpHub: { ...view, servers: signed ? view.servers : [] } }],
      'mcp-assign': (request) => [{ id: request.id, ok: true, proposed: 'prp_2' }],
    });
    const hub = new McpHub(daemon, new RequestIds());
    hub.giveOnceAdded('github', ['codex-cli']);
    await hub.refresh();
    expect(daemon.sent('mcp-assign')).toHaveLength(0);
    signed = true;
    await hub.refresh();
    await hub.refresh();
    expect(daemon.sent('mcp-assign')).toHaveLength(1);
  });
});

describe('an organization server', () => {
  it('is read only on this computer', () => {
    expect(fromOrganization({ scope: 'organization' })).toBe(true);
    expect(fromOrganization({ scope: 'personal' })).toBe(false);
  });
});

describe('an assignment held to one repository', () => {
  const server = {
    projects: [
      { agent: 'claude-code', project: '/Users/bo/code/billing' },
      { agent: 'cursor', project: 'C:\\Users\\bo\\code\\web\\' },
    ],
  };

  it('is named by its folder, with the full path for the tooltip', () => {
    expect(projectsFor(server, 'claude-code')).toEqual([{ name: 'billing', path: '/Users/bo/code/billing' }]);
    expect(projectFolder('C:\\Users\\bo\\code\\web\\')).toBe('web');
    expect(projectHelp('claude-code', '/Users/bo/code/billing')).toBe('Given to Claude Code in /Users/bo/code/billing only');
  });

  it('names nothing for an agent given it everywhere, or a runtime that sends no projects', () => {
    expect(projectsFor(server, 'codex-cli')).toEqual([]);
    expect(projectsFor({}, 'claude-code')).toEqual([]);
  });
});

describe('how far an agent has a server', () => {
  // The runtime lists an agent once per assignment, so Claude Code here has it everywhere and in billing too.
  const server = {
    agents: ['claude-code', 'claude-code', 'cursor'],
    projects: [
      { agent: 'claude-code', project: '/Users/bo/code/billing' },
      { agent: 'cursor', project: '/Users/bo/code/web' },
    ],
  };

  it('tells everywhere from a project only assignment and from none', () => {
    expect(reachOf(server, 'claude-code')).toBe('everywhere');
    expect(reachOf(server, 'cursor')).toBe('projects');
    expect(reachOf(server, 'codex-cli')).toBe('none');
    expect(reachOf({ agents: ['codex-cli'] }, 'codex-cli')).toBe('everywhere');
  });

  it('says each reach under the agent, naming the project when there is one', () => {
    expect(reachCaption(server, 'claude-code')).toBe('Has this server in every project');
    expect(reachCaption(server, 'cursor')).toBe('Has this server only in web');
    expect(reachCaption(server, 'codex-cli')).toBeUndefined();
    const twice = { agents: ['cursor', 'cursor'], projects: [{ agent: 'cursor', project: '/a/web' }, { agent: 'cursor', project: '/a/api' }] };
    expect(reachCaption(twice, 'cursor')).toBe('Has this server only in 2 projects');
  });

  it('sends a project only assignment to Projects, where it is given', () => {
    expect(projectOnlyHelp(server, 'cursor')).toBe("Cursor has this server only in /Users/bo/code/web, given in that project's settings in Projects.");
    expect(PROJECT_ONLY_LINE).toBe("A folder means the agent has this server only in that project. It is given in that project's settings, so it is changed in Projects, and giving it here gives it in every project.");
  });

  it('offers a project only agent the server in every project, never a take away', () => {
    expect(GIVE_EVERYWHERE).toBe('Give in every project');
    expect(reachOf(server, 'cursor')).not.toBe('everywhere');
  });
});

describe('a remote server’s headers', () => {
  it('keeps a credential header as a secret from its name, whatever its case', () => {
    expect(isCredentialHeader('Authorization')).toBe(true);
    expect(isCredentialHeader('x-api-key')).toBe(true);
    expect(isCredentialHeader('Cookie')).toBe(true);
    expect(isCredentialHeader('X-Trace')).toBe(false);
  });

  it('refuses a credential sent plain, a bad name, a repeat and an empty value, as the runtime would', () => {
    expect(headerProblem([{ name: 'Authorization', value: 'Bearer abc', secret: false }])).toBe('Authorization carries a credential, so keep its value as a secret.');
    expect(headerProblem([{ name: 'Bad Name', value: 'x', secret: false }])).toBe('Bad Name is not a header name.');
    expect(headerProblem([{ name: 'X-Team', value: 'a', secret: false }, { name: 'x-team', value: 'b', secret: false }])).toBe('x-team is given twice.');
    expect(headerProblem([{ name: 'X-Team', value: ' ', secret: false }])).toBe('Give the value X-Team is sent with.');
    expect(headerProblem([{ name: '', value: '', secret: false }, { name: 'Authorization', value: 'Bearer abc', secret: true }])).toBeUndefined();
  });

  it('sends a kept header as its reference, the token scheme kept in front', () => {
    expect(headerSecretName('docs', 'X-Api-Key')).toBe('docs-x-api-key');
    expect(headerReference('Bearer abc.def', 'docs-authorization')).toEqual({ sent: 'Bearer memnox-secret:docs-authorization', secret: 'abc.def' });
    expect(headerReference('abc', 'docs-x-api-key')).toEqual({ sent: 'memnox-secret:docs-x-api-key', secret: 'abc' });
    expect(headersOf('docs', [{ name: 'Authorization', value: 'Bearer abc', secret: true }, { name: 'X-Team', value: 'core', secret: false }])).toEqual({
      headers: { Authorization: 'Bearer memnox-secret:docs-authorization', 'X-Team': 'core' },
      secrets: { 'docs-authorization': 'abc' },
    });
  });

  it('takes plain http only for this computer', () => {
    expect(remoteAddressProblem('https://mcp.example.com/mcp')).toBeUndefined();
    expect(remoteAddressProblem('http://localhost:3000/mcp')).toBeUndefined();
    expect(remoteAddressProblem('http://127.0.0.1:3000/mcp')).toBeUndefined();
    expect(remoteAddressProblem('http://mcp.example.com/mcp')).toBe('Plain http is only for a server on this computer, at localhost or 127.0.0.1. Use https for one anywhere else.');
    expect(remoteAddressProblem('ftp://example.com')).toBe('A remote server is reached over http or https.');
    expect(remoteAddressProblem('mcp.example')).toBe('mcp.example is not an address.');
  });

  it('lists headers by name, with whether the secret the dialog named is held', () => {
    expect(headerLines({ name: 'docs', headerNames: ['Authorization', 'X-Team'], secretsHeld: { 'docs-authorization': false } })).toEqual([{ name: 'Authorization', held: false }, { name: 'X-Team' }]);
    expect(headerLines({ name: 'docs', secretsHeld: {} })).toEqual([]);
  });
});

describe('what each row of the hub says', () => {
  it('names the agents a server is given to once each', () => {
    expect(usedBy({ agents: ['claude-code', 'cursor', 'claude-code', 'codex-cli'] })).toBe('Claude Code, Cursor and Codex');
    expect(usedBy({ agents: [] })).toBe('Given to no agent yet');
    expect(transportWord({ transport: 'http' })).toBe('Remote');
  });

  it('keeps each press on its own row, waiting until a newer hub shows it written', async () => {
    const server = { name: 'github', agents: [] as string[] };
    const daemon = new ScriptedDaemon({
      'mcp-assign': (request) => [{ id: request.id, ok: true, proposed: 'prp_1', outcome: 'It gives Codex your repositories' }],
      'mcp-hub': (request) => [{ id: request.id, ok: true, mcpHub: { servers: [{ ...server, agents: ['codex-cli'] }] } as never }],
    });
    const hub = new McpHub(daemon, new RequestIds());
    await hub.assign('github', 'codex-cli', true);
    const pair = McpHub.pair('github', 'codex-cli');
    expect(hub.press(pair)?.kind).toBe('waiting');
    expect(pressLine(hub.press(pair), 'Windows Hello')?.text).toBe('Waiting for Windows Hello on the island. It gives Codex your repositories');
    await hub.refresh();
    expect(hub.press(pair)).toEqual({ kind: 'done', line: 'Codex has github now.' });
    hub.clear(pair);
    expect(hub.press(pair)).toBeUndefined();
  });
});

describe('the line after Add server', () => {
  it('says who it waits on and who is asked next, as the Mac does', async () => {
    const { addedLine, COMMAND_HINT } = await import('../src/core/domain/mcp-hub-lines');
    expect(addedLine({ kind: 'waiting', note: 'It runs uvx mcp-server-git.' }, 'git', ['claude-code', 'claude-code'], 'Windows Hello')).toBe(
      'git waits for Windows Hello on the island. It runs uvx mcp-server-git. Once it is signed, giving it to Claude Code and Claude Code asks for Windows Hello again.',
    );
    expect(addedLine({ kind: 'waiting', note: undefined }, 'git', [], 'Windows Hello')).toBe('git waits for Windows Hello on the island.');
    expect(addedLine({ kind: 'done', line: 'git is in the hub.' }, 'git', [], 'Windows Hello')).toBe('git is in the hub.');
    expect(COMMAND_HINT).toContain('Memnox starts it with the runner that installs it.');
  });
});
