import type { McpHubServerView, McpServerHealth } from '@memnox/core/wire';

/** The words and tone a server's health is shown with, the tone always beside its word. */
export function healthWords(health: McpServerHealth): { word: string; tone: 'good' | 'bad' | 'quiet' } {
  if (health.state === 'healthy') return { word: 'Answering', tone: 'good' };
  if (health.state === 'error') return { word: 'Not answering', tone: 'bad' };
  return { word: 'Not tested yet', tone: 'quiet' };
}

export function toolsLine(count: number): string {
  if (count === 0) return 'No tools listed yet';
  return count === 1 ? '1 tool' : `${count} tools`;
}

export function callsLine(count: number): string {
  if (count === 0) return 'No calls this week';
  return count === 1 ? '1 call this week' : `${count} calls this week`;
}

export function agentsLine(count: number): string {
  if (count === 0) return 'Given to no agent yet';
  return count === 1 ? 'Given to 1 agent' : `Given to ${count} agents`;
}

/** What one card says under the name: how it is reached, without the arguments, which can be long. */
export function launchLine(server: Pick<McpHubServerView, 'transport' | 'command' | 'url'>): string {
  if (server.transport === 'http') return server.url ?? 'A remote server';
  return server.command ?? 'A local server';
}

/** Secrets a server names that this computer does not hold, which keep it from starting. */
export function missingSecrets(server: Pick<McpHubServerView, 'secretsHeld'>): string[] {
  return Object.entries(server.secretsHeld)
    .filter(([, held]) => !held)
    .map(([name]) => name);
}

/** Every secret named across the hub, with the servers that use it and whether it is held. */
export function secretsAcross(servers: readonly Pick<McpHubServerView, 'name' | 'secretsHeld'>[]): { name: string; held: boolean; usedBy: string[] }[] {
  const byName = new Map<string, { held: boolean; usedBy: string[] }>();
  for (const server of servers) {
    for (const [name, held] of Object.entries(server.secretsHeld)) {
      const entry = byName.get(name) ?? { held, usedBy: [] };
      entry.usedBy.push(server.name);
      byName.set(name, { held: entry.held && held, usedBy: entry.usedBy });
    }
  }
  return [...byName].map(([name, entry]) => ({ name, ...entry })).sort((a, b) => a.name.localeCompare(b.name));
}

/** A word a person typed turned into a name the hub and every agent's config accept. */
export function serverNameFrom(typed: string): string {
  return typed
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^[^a-z0-9]+/, '')
    .slice(0, 64);
}

/** A launch line typed in one field, split the way a shell would for plain words and quoted ones. */
export function splitCommand(line: string): { command: string; args: string[] } | undefined {
  const words = line.match(/"[^"]*"|'[^']*'|\S+/g)?.map((word) => word.replace(/^(["'])(.*)\1$/, '$2')) ?? [];
  const [command, ...args] = words;
  return command === undefined ? undefined : { command, args };
}

/** The name an agent goes by, from the kind the runtime reports; an unknown kind is shown as it is. */
const AGENT_NAMES: Readonly<Record<string, string>> = {
  'claude-code': 'Claude Code',
  'claude-desktop': 'Claude Desktop',
  'codex-cli': 'Codex',
  cursor: 'Cursor',
  cline: 'Cline',
  vscode: 'VS Code',
  'gemini-cli': 'Gemini CLI',
  windsurf: 'Windsurf',
  'copilot-cli': 'Copilot CLI',
  opencode: 'OpenCode',
  hermes: 'Hermes',
  openclaw: 'OpenClaw',
  devin: 'Devin',
  ruflo: 'Ruflo',
};

export function agentLabel(kind: string): string {
  return AGENT_NAMES[kind] ?? kind;
}

/** An organization's server is read only here: it is given, changed and removed in Memnox Cloud. */
export function fromOrganization(server: Pick<McpHubServerView, 'scope'>): boolean {
  return server.scope === 'organization';
}

export const ORGANIZATION_WORD = 'From your organization';
export const ORGANIZATION_LINE = 'Your organization set this server up, so who has it is changed in Memnox Cloud rather than here.';
