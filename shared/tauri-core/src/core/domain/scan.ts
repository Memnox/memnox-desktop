import type { AgentNode } from '@memnox/core/wire';

/**
 * The scan screen, ported from the Mac's `ScanOverlay`: every agent on this computer around a ring,
 * with what each reaches, and the totals along the bottom.
 */

/** How long the scan screen stays, and the pace its agents arrive at. */
export const SCAN_TIMING = { showMs: 25_000, fadeOutMs: 350, warmUpMs: 700, perAgentMs: 320, countUpMs: 900, countUpDelayMs: 200 } as const;

/** The ring's radii as a share of the screen, capped so a very large display does not scatter the cards. */
export function scanRing(size: { width: number; height: number }): { width: number; height: number } {
  return { width: Math.min(size.width * 0.34, 560), height: Math.min(size.height * 0.29, 320) };
}

/** Where agent `index` of `count` sits on the ring, the first at the top and the rest clockwise. */
export function ringPoint(index: number, count: number, centre: { x: number; y: number }, ring: { width: number; height: number }): { x: number; y: number } {
  const step = (2 * Math.PI) / Math.max(count, 1);
  const angle = -Math.PI / 2 + step * index;
  return { x: centre.x + ring.width * Math.cos(angle), y: centre.y + ring.height * Math.sin(angle) };
}

/** The dot between items in a line. */
const SEPARATOR = ' · ';
const REACH_SHOWN = 3;
const SERVERS_SHOWN = 3;
const CLIS_SHOWN = 4;
const SPOKEN: Record<string, string> = { filesystem: 'files' };

/** A few by name and the rest as a count, so one card never grows wider than the ring allows. */
function listed(names: readonly string[], most: number): string {
  const shown = names.slice(0, most).join(SEPARATOR);
  return names.length > most ? `${shown} +${names.length - most}` : shown;
}

/** Counted facts only: its MCP servers and the kinds of thing it can touch. */
export function reachLine(agent: Pick<AgentNode, 'servers' | 'reaches'>): string {
  const servers = agent.servers === 0 ? [] : [`${agent.servers} MCP ${agent.servers === 1 ? 'server' : 'servers'}`];
  const words = agent.reaches.slice(0, REACH_SHOWN).map((each) => SPOKEN[each] ?? each);
  const parts = [...servers, ...words];
  return parts.length === 0 ? 'nothing beyond its own app' : parts.join(SEPARATOR);
}

/** What it is connected to by name: its MCP servers with their tools, then the CLIs signed in for its shell. */
export function connectionLines(agent: Pick<AgentNode, 'mcp' | 'clis'>): string[] {
  const servers = (agent.mcp ?? []).map((server) => (server.tools === undefined ? server.name : `${server.name} ${server.tools}`));
  const lines: string[] = [];
  if (servers.length > 0) lines.push(`mcp  ${listed(servers, SERVERS_SHOWN)}`);
  if (agent.clis !== undefined && agent.clis.length > 0) lines.push(`cli  ${listed(agent.clis, CLIS_SHOWN)}`);
  return lines;
}

/** The status pill, working before waiting, or none for an agent at rest. */
export function agentStatus(agent: Pick<AgentNode, 'working' | 'open'>): { text: string; tone: 'green' | 'amber' } | undefined {
  if (agent.working > 0) return { text: agent.working === 1 ? '1 working' : `${agent.working} working`, tone: 'green' };
  if (agent.open > 0) return { text: agent.open === 1 ? '1 waiting on you' : `${agent.open} waiting on you`, tone: 'amber' };
  return undefined;
}

/** The totals along the bottom. */
export function scanTotals(agents: readonly AgentNode[]): { agents: number; tools: number; changing: number; working: number } {
  let tools = 0;
  let changing = 0;
  let working = 0;
  for (const agent of agents) {
    working += agent.working;
    for (const server of agent.mcp ?? []) {
      tools += server.tools ?? 0;
      changing += server.changing ?? 0;
    }
  }
  return { agents: agents.length, tools, changing, working };
}

/** The heading under the badge: "1 agent on this computer" or "4 agents on this computer". */
export function scanCountLabel(total: number): string {
  return total === 1 ? 'agent on this computer' : 'agents on this computer';
}
