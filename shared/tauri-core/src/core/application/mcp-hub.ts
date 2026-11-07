import { MCP_HUB_METHOD, type DaemonRequest, type DaemonResponse, type McpHubView, type McpServerHealth } from '@memnox/core/wire';
import { agentLabel, reachOf } from '../domain/mcp-hub-lines';
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
 * Where the last press on one server, pair, found line or secret stands, for its own row to say, as the Mac's
 * `McpPress`: with the runtime now, waiting on a signature on the island, done, or refused.
 */
export type McpPress = { kind: 'working' } | { kind: 'waiting'; note: string | undefined } | { kind: 'done'; line: string } | { kind: 'failed'; why: string };

/** A proposal this hub raised and still waits on, with how to tell from a newer hub that it was written. */
interface Awaited {
  readonly subject: string;
  readonly landed: (hub: McpHubView) => boolean;
  readonly done: string;
}

/**
 * The MCP Hub as the runtime keeps it: servers set up once, given to the agents the person chose. It
 * holds no rule: the runtime writes every config, and a change that gives an agent more waits for a signature.
 */
export class McpHub extends Observed {
  private view: McpHubView | undefined;
  private failed = false;
  private readonly tests = new Map<string, McpServerHealth>();
  private readonly presses = new Map<string, McpPress>();
  private readonly awaiting = new Map<string, Awaited>();
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

  /** The server, pair, found line or secret a press is still working on, so its button can say so. */
  get busy(): string | undefined {
    for (const [subject, press] of this.presses) if (press.kind === 'working') return subject;
    return undefined;
  }

  /** Where the last press on one row stands. */
  press(subject: string): McpPress | undefined {
    return this.presses.get(subject);
  }

  /** Forgets what a row says, once the person has read it and moves on. */
  clear(subject: string): void {
    if (this.presses.get(subject)?.kind !== 'working') this.presses.delete(subject);
    this.changed();
  }

  /** The key one server given to or taken from one agent is pressed under. */
  static pair(server: string, agent: string): string {
    return `${server}/${agent}`;
  }

  /** The key a press on one found line is kept under, apart from a hub server of the same name. */
  static found(server: string, agent: string): string {
    return `found/${agent}/${server}`;
  }

  /** A test run here, newer than the one the view carries. */
  testOf(server: string): McpServerHealth | undefined {
    return this.tests.get(server);
  }

  async refresh(): Promise<void> {
    const response = await this.ask({ method: MCP_HUB_METHOD.HUB });
    this.failed = response === undefined || !response.ok;
    if (response?.mcpHub !== undefined) this.see(response.mcpHub);
    this.changed();
    await this.giveWhatWaits();
  }

  /** Remembers who a new server is for, since giving it can only be asked once it is signed into the hub. */
  giveOnceAdded(server: string, agents: readonly string[]): void {
    if (agents.length > 0) this.pendingGives.set(server, agents);
  }

  /** A newer hub, and every awaited proposal it shows written is said done on its row. */
  private see(hub: McpHubView): void {
    this.view = hub;
    for (const [id, each] of [...this.awaiting]) {
      if (!each.landed(hub)) continue;
      this.awaiting.delete(id);
      this.presses.set(each.subject, { kind: 'done', line: each.done });
    }
  }

  private async giveWhatWaits(): Promise<void> {
    // A server being replaced is in the hub already, so its agents wait for the replacement to be signed.
    const signing = new Set([...this.awaiting.values()].map((each) => each.subject));
    for (const [server, agents] of [...this.pendingGives]) {
      if (this.view?.servers.some((each) => each.name === server) !== true || signing.has(server)) continue;
      this.pendingGives.delete(server);
      for (const agent of agents) await this.assign(server, agent, true);
    }
  }

  putServer(server: HubServerDraft): Promise<HubOutcome> {
    const name = server.name;
    return this.change(name, { method: MCP_HUB_METHOD.SERVER_PUT, mcpServer: server }, `${name} is in the hub.`, (hub) => hub.servers.some((each) => each.name === name));
  }

  removeServer(name: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SERVER_REMOVE, mcpServerName: name }, `${name} was removed from every agent.`);
  }

  assign(server: string, agent: string, on: boolean): Promise<HubOutcome> {
    const label = agentLabel(agent);
    const note = on ? `${label} has ${server} now.` : `${label} no longer has ${server}.`;
    const landed = (hub: McpHubView) => {
      const found = hub.servers.find((each) => each.name === server);
      return found !== undefined && (reachOf(found, agent) === 'everywhere') === on;
    };
    return this.change(McpHub.pair(server, agent), { method: MCP_HUB_METHOD.ASSIGN, mcpServerName: server, mcpAgent: agent, mcpOn: on }, note, landed);
  }

  importServer(agent: string, server: string): Promise<HubOutcome> {
    return this.change(McpHub.found(server, agent), { method: MCP_HUB_METHOD.IMPORT, mcpServerName: server, mcpAgent: agent }, `${server} is in the hub now, governed for ${agentLabel(agent)}.`);
  }

  sync(): Promise<HubOutcome> {
    return this.change('sync', { method: MCP_HUB_METHOD.SYNC });
  }

  async test(server: string): Promise<HubOutcome> {
    this.begin(server);
    const response = await this.ask({ method: MCP_HUB_METHOD.TEST, mcpServerName: server });
    if (response === undefined || !response.ok) return this.refused(server, failure(response));
    const line = response.mcpHealth?.state === 'healthy' ? `${server} answered.` : `${server} did not answer.`;
    if (response.mcpHealth !== undefined) this.tests.set(server, response.mcpHealth);
    this.presses.set(server, { kind: 'done', line });
    if (response.mcpHub !== undefined) this.see(response.mcpHub);
    this.changed();
    return { kind: 'done', note: line };
  }

  /** The value goes straight to the runtime over this computer's own socket, and the window keeps no copy. */
  setSecret(name: string, value: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SECRET_SET, mcpSecret: name, mcpSecretValue: value }, `${name} is kept by this computer now.`);
  }

  removeSecret(name: string): Promise<HubOutcome> {
    return this.change(name, { method: MCP_HUB_METHOD.SECRET_REMOVE, mcpSecret: name }, `${name} was removed from this computer.`);
  }

  /** One press: the runtime's answer kept for its row, and a proposal remembered until a hub shows it written. */
  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done = 'Done.', landed?: (hub: McpHubView) => boolean): Promise<HubOutcome> {
    this.begin(subject);
    const response = await this.ask(fields);
    if (response === undefined || !response.ok) return this.refused(subject, failure(response));
    let outcome: HubOutcome;
    if (response.proposed !== undefined) {
      outcome = { kind: 'proposed', id: response.proposed };
      this.presses.set(subject, { kind: 'waiting', note: response.outcome });
      if (landed !== undefined) this.awaiting.set(response.proposed, { subject, landed, done });
    } else {
      outcome = { kind: 'done', note: response.mcpSynced !== undefined ? syncedLine(response.mcpSynced) : done };
      this.presses.set(subject, { kind: 'done', line: outcome.note });
    }
    if (response.mcpHub !== undefined) this.see(response.mcpHub);
    this.changed();
    return outcome;
  }

  private refused(subject: string, why: string): HubOutcome {
    this.presses.set(subject, { kind: 'failed', why });
    this.changed();
    return { kind: 'failed', why };
  }

  private begin(subject: string): void {
    this.presses.set(subject, { kind: 'working' });
    this.changed();
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
