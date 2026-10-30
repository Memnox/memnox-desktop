import type { DaemonRequest, McpHubView } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { McpHub, syncedLine } from '../src/core/application/mcp-hub';
import { RequestIds } from '../src/core/application/request-ids';
import { missingSecrets, secretsAcross, serverNameFrom, splitCommand } from '../src/core/domain/mcp-hub-lines';
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
