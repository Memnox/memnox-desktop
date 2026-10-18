import { DAEMON_METHOD, type ToolConnection, type VoiceAgentStatus } from '@memnox/core/wire';
import type { ToolChip } from '../domain/menu-panel';
import { toolkitName } from '../domain/tool-brand';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** The person's agents and connected apps, as the tray panel, the island and Settings all show them. */
export interface ToolsState {
  /** The agents installed here, the voice's own first. */
  readonly agents: readonly VoiceAgentStatus[];
  readonly connections: readonly ToolConnection[];
  /** Why the connected apps could not be read, said where they would be. */
  readonly connectionsNote: string | undefined;
  /** True until the first read lands, so an empty list is not mistaken for none. */
  readonly reading: boolean;
}

/** Said when the daemon does not answer at all. */
const UNREACHABLE = 'Memnox is not running';

/**
 * The agents on this computer and the person's own connected apps, read from the daemon once for every
 * screen, so the panel, the tools grid and Settings always show the same list. Ported from the Mac's
 * `ToolsModel`; the panel asks again each time it opens, since either list changes without telling.
 */
export class Tools {
  private current: ToolsState = { agents: [], connections: [], connectionsNote: undefined, reading: true };
  private readonly listeners = new Set<() => void>();
  private inFlight: Promise<void> | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {}

  get state(): ToolsState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Reads both lists again; a read already under way is the one that answers. */
  refresh(): Promise<void> {
    this.inFlight ??= this.read().finally(() => (this.inFlight = undefined));
    return this.inFlight;
  }

  get connectedCount(): number {
    return this.current.connections.filter((each) => each.connected).length;
  }

  /** The strip's chips: agents first, then apps. */
  get chips(): ToolChip[] {
    return toolChips(this.current);
  }

  private async read(): Promise<void> {
    const [agents, connections] = await Promise.all([this.ask(DAEMON_METHOD.VOICE_AGENTS), this.ask(DAEMON_METHOD.CONNECTIONS_LIST)]);
    let next: ToolsState = { ...this.current, reading: false };
    if (agents?.ok === true && agents.voiceAgents !== undefined) {
      next = { ...next, agents: [...agents.voiceAgents].filter((each) => each.installed).sort((a, b) => Number(b.chosen) - Number(a.chosen)) };
    }
    if (connections === undefined) next = { ...next, connectionsNote: UNREACHABLE };
    else if (!connections.ok) next = { ...next, connections: [], connectionsNote: connections.error ?? 'Memnox could not read your apps' };
    else next = { ...next, connections: connections.connections ?? [], connectionsNote: undefined };
    this.current = next;
    for (const listener of this.listeners) listener();
  }

  private async ask(method: (typeof DAEMON_METHOD)[keyof typeof DAEMON_METHOD]) {
    return requestOnce(this.link, { id: this.ids.next(), method }).catch(() => undefined);
  }
}

/** The strip's chips from what the daemon said: agents first, then apps. */
export function toolChips(state: Pick<ToolsState, 'agents' | 'connections'>): ToolChip[] {
  return [
    ...state.agents.map((agent) => ({ id: `agent:${agent.kind}`, kind: 'agent' as const, key: agent.kind, name: agent.label, ready: agent.works !== false })),
    ...state.connections.map((app) => ({ id: `app:${app.toolkit}`, kind: 'app' as const, key: app.toolkit, name: toolkitName(app.toolkit), ready: app.connected })),
  ];
}

/** What a tool's tile says under its name, as the Mac's `ToolStatus`. */
export function agentStatusWord(agent: Pick<VoiceAgentStatus, 'chosen' | 'works'>): string {
  if (agent.chosen) return 'Voice';
  if (agent.works === false) return 'Not the voice yet';
  return 'Ready';
}

export function connectionStatusWord(connection: Pick<ToolConnection, 'connected'>): string {
  return connection.connected ? 'Connected' : 'Sign in again';
}
