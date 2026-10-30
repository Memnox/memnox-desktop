import { MCP_HUB_METHOD, type DaemonRequest, type DaemonResponse, type McpHubView, type McpServerHealth } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** A server as the Add form fills it, secrets by name only; the wire carries it as `mcpServer`. */
export type HubServerDraft = NonNullable<DaemonRequest['mcpServer']>;

/** How one press on the hub ended, said in a line under it. */
export type HubOutcome =
  /** Done at once: narrowing changes, imports and syncs need no signature. */
  | { kind: 'done'; note: string }
  /** A widening change waits on the island for the person's signature. */
  | { kind: 'proposed'; id: string }
  | { kind: 'failed'; why: string };

/**
 * The MCP Hub as the runtime keeps it: servers set up once, given to the agents the person chose. It
 * holds no rule: the runtime writes every config, and a change that gives an agent more waits for a signature.
 */
export class McpHub extends Observed {
  private view: McpHubView | undefined;
  private failed = false;
  private readonly tests = new Map<string, McpServerHealth>();
  private busyWith: string | undefined;
  /** Agents chosen while adding a server that is not signed yet, given once the hub holds it. */
  private readonly pendingGives = new Map<string, readonly string[]>();

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get hub(): McpHubView | undefined {
    return this.view;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** The server or secret a press is still working on, so its button can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  /** A test run here, newer than the one the view carries. */
  testOf(server: string): McpServerHealth | undefined {
    return this.tests.get(server);
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: MCP_HUB_METHOD.HUB });
    this.failed = response === undefined || !response.ok;
    if (response?.mcpHub !== undefined) this.view = response.mcpHub;
    this.changed();
    await this.giveWhatWaits();
  }

  /** Remembers who a new server is for, since giving it can only be asked once it is signed into the hub. */
  giveOnceAdded(server: string, agents: readonly string[]): void {
    if (agents.length > 0) this.pendingGives.set(server, agents);
  }

  private async giveWhatWaits(): Promise<void> {
    for (const [server, agents] of [...this.pendingGives]) {
      if (this.view?.servers.some((each) => each.name === server) !== true) continue;
      this.pendingGives.delete(server);
      for (const agent of agents) await this.assign(server, agent, true);
    }
  }

  putServer(server: HubServerDraft): Promise<HubOutcome> {
    return this.change(server.name, { method: MCP_HUB_METHOD.SERVER_PUT, mcpServer: server });
  }

  removeServer(name: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SERVER_REMOVE, mcpServerName: name }, `${name} was removed from every agent.`);
  }

  assign(server: string, agent: string, on: boolean): Promise<HubOutcome> {
    const note = on ? `${server} is now given to ${agent}.` : `${agent} no longer has ${server}.`;
    return this.change(`${server}/${agent}`, { method: MCP_HUB_METHOD.ASSIGN, mcpServerName: server, mcpAgent: agent, mcpOn: on }, note);
  }

  importServer(agent: string, server: string): Promise<HubOutcome> {
    return this.change(server, { method: MCP_HUB_METHOD.IMPORT, mcpServerName: server, mcpAgent: agent }, `${server} is in the hub now, governed for ${agent}.`);
  }

  sync(): Promise<HubOutcome> {
    return this.change('sync', { method: MCP_HUB_METHOD.SYNC });
  }

  async test(server: string): Promise<HubOutcome> {
    this.begin(server);
    const response = await this.ask({ method: MCP_HUB_METHOD.TEST, mcpServerName: server });
    this.end();
    if (response === undefined || !response.ok) return { kind: 'failed', why: failure(response) };
    if (response.mcpHealth !== undefined) this.tests.set(server, response.mcpHealth);
    if (response.mcpHub !== undefined) this.view = response.mcpHub;
    this.changed();
    return { kind: 'done', note: response.mcpHealth?.state === 'healthy' ? `${server} answered.` : `${server} did not answer.` };
  }

  /** The value goes straight to the runtime over this computer's own socket, and the window keeps no copy. */
  setSecret(name: string, value: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SECRET_SET, mcpSecret: name, mcpSecretValue: value }, `${name} is kept by this computer now.`);
  }

  removeSecret(name: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SECRET_REMOVE, mcpSecret: name }, `${name} was removed from this computer.`);
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done = 'Done.'): Promise<HubOutcome> {
    this.begin(subject);
    const response = await this.ask(fields);
    this.end();
    if (response === undefined || !response.ok) return { kind: 'failed', why: failure(response) };
    if (response.mcpHub !== undefined) this.view = response.mcpHub;
    this.changed();
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
    if (response.mcpSynced !== undefined) return { kind: 'done', note: syncedLine(response.mcpSynced) };
    return { kind: 'done', note: done };
  }

  private begin(subject: string): void {
    this.busyWith = subject;
    this.changed();
  }

  private end(): void {
    this.busyWith = undefined;
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a method the hub answers and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}

function failure(response: DaemonResponse | undefined): string {
  if (response === undefined) return 'The runtime is not answering.';
  return response.error ?? 'The runtime refused this.';
}

/** "Wrote 2 configs: 1 added, 1 removed." or that nothing needed writing. */
export function syncedLine(synced: { added: number; updated: number; removed: number; files: readonly string[] }): string {
  const parts = [
    synced.added > 0 ? `${synced.added} added` : undefined,
    synced.updated > 0 ? `${synced.updated} updated` : undefined,
    synced.removed > 0 ? `${synced.removed} removed` : undefined,
  ].filter((part): part is string => part !== undefined);
  if (parts.length === 0) return 'Every agent already has what the hub gives it.';
  const files = synced.files.length === 1 ? '1 config' : `${synced.files.length} configs`;
  return `Wrote ${files}: ${parts.join(', ')}.`;
}
