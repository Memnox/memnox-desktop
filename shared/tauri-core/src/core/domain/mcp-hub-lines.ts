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

/** A repository's folder name from its absolute path, on either separator, so a chip stays short. */
export function projectFolder(path: string): string {
  const parts = path.split(/[\\/]+/).filter((part) => part !== '');
  return parts.at(-1) ?? path;
}

/** The repositories one agent was given a server in, each by folder name with its full path for the tooltip. */
export function projectsFor(server: Pick<McpHubServerView, 'projects'>, agent: string): { name: string; path: string }[] {
  return (server.projects ?? []).filter((each) => each.agent === agent).map((each) => ({ name: projectFolder(each.project), path: each.project }));
}

/** What a project chip's tooltip says: whose assignment it is and the repository in full. */
export function projectHelp(agent: string, path: string): string {
  return `Given to ${agentLabel(agent)} in ${path} only`;
}

/** How far one agent has a server: in every project, only in the repositories named, or not at all. */
export type AgentReach = 'everywhere' | 'projects' | 'none';

/**
 * The runtime lists an agent in `agents` once per assignment, a repository's included, so an agent counted
 * there more often than in `projects` also has it everywhere.
 */
export function reachOf(server: Pick<McpHubServerView, 'agents' | 'projects'>, agent: string): AgentReach {
  const given = server.agents.filter((each) => each === agent).length;
  const inProjects = (server.projects ?? []).filter((each) => each.agent === agent).length;
  if (given > inProjects) return 'everywhere';
  return inProjects > 0 ? 'projects' : 'none';
}

/** What an agent's row says under its name, for each reach, so a project only assignment never reads as everywhere. */
export function reachCaption(server: Pick<McpHubServerView, 'agents' | 'projects'>, agent: string): string | undefined {
  const reach = reachOf(server, agent);
  if (reach === 'everywhere') return 'Has this server in every project';
  if (reach === 'none') return undefined;
  const projects = projectsFor(server, agent);
  const [only] = projects;
  return projects.length === 1 && only !== undefined ? `Has this server only in ${only.name}` : `Has this server only in ${projects.length} projects`;
}

/** Why a project only assignment is never taken away here: unticking would remove nothing. */
export const PROJECT_ONLY_LINE = "A folder means the agent has this server only in that project. It is given in that project's settings, so it is changed in Workspaces, and giving it here gives it in every project.";
/** The control beside a project only assignment: it gives the server everywhere, signed like every other give. */
export const GIVE_EVERYWHERE = 'Give in every project';
export const WORKSPACES_LINK = 'Open Workspaces';

/** The help on a project only cell: who has it, where, and where it is changed. */
export function projectOnlyHelp(server: Pick<McpHubServerView, 'projects'>, agent: string): string {
  const paths = projectsFor(server, agent).map((each) => each.path);
  return `${agentLabel(agent)} has this server only in ${paths.join(', ')}, given in that project's settings in Workspaces.`;
}

/** One header row as the Add server dialog fills it: a name, the value as typed, and whether this computer keeps it. */
export interface HeaderRow {
  readonly name: string;
  readonly value: string;
  readonly secret: boolean;
}

/** Headers that carry a credential, which the runtime refuses unless their value is a secret reference. */
const CREDENTIAL_HEADERS: readonly string[] = ['authorization', 'proxy-authorization', 'cookie', 'x-api-key', 'api-key'];
/** A header's name as HTTP spells a token, the runtime's own check. */
const HEADER_NAME = /^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/;
/** How a header value names a kept secret, which the proxy swaps for the secret on every request. */
export const SECRET_REFERENCE = 'memnox-secret:';
/** A scheme a token is written after, kept in front of the reference so the server still reads `Bearer <token>`. */
const TOKEN_SCHEME = /^(Bearer|Basic|Token|Bot)\s+(\S.*)$/i;
/** The longest secret name the runtime keeps. */
const SECRET_NAME_LENGTH = 64;
/** Plain http is for a server on this computer only, since a header may carry a credential. */
const LOOPBACK_HOSTS: readonly string[] = ['localhost', '127.0.0.1', '[::1]'];

/** Whether a header carries a credential, so its row starts kept as a secret and cannot be sent plain. */
export function isCredentialHeader(name: string): boolean {
  return CREDENTIAL_HEADERS.includes(name.trim().toLowerCase());
}

/** The name this computer keeps a header's secret under, from the server's and the header's names. */
export function headerSecretName(server: string, header: string): string {
  return `${server}-${header.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '-')}`.slice(0, SECRET_NAME_LENGTH);
}

/** What a kept header is sent as, a scheme in front kept as typed, and the secret itself, which goes to this computer's store. */
export function headerReference(value: string, secretName: string): { sent: string; secret: string } {
  const scheme = TOKEN_SCHEME.exec(value.trim());
  if (scheme === null) return { sent: `${SECRET_REFERENCE}${secretName}`, secret: value.trim() };
  return { sent: `${scheme[1] ?? ''} ${SECRET_REFERENCE}${secretName}`, secret: scheme[2] ?? '' };
}

/** What is wrong with the header rows, said as the runtime would refuse it, or undefined when they can be sent. */
export function headerProblem(rows: readonly HeaderRow[]): string | undefined {
  const seen = new Set<string>();
  for (const row of rows.filter((each) => each.name.trim() !== '')) {
    const name = row.name.trim();
    if (!HEADER_NAME.test(name)) return `${name} is not a header name.`;
    if (seen.has(name.toLowerCase())) return `${name} is given twice.`;
    seen.add(name.toLowerCase());
    if (isCredentialHeader(name) && !row.secret) return `${name} carries a credential, so keep its value as a secret.`;
    if (row.value.trim() === '') return `Give the value ${name} is sent with.`;
  }
  return undefined;
}

/** The headers as the server is written with them, a kept one as its reference, and the secrets to keep first by name. */
export function headersOf(server: string, rows: readonly HeaderRow[]): { headers: Record<string, string>; secrets: Record<string, string> } {
  const headers: Record<string, string> = {};
  const secrets: Record<string, string> = {};
  for (const row of rows.filter((each) => each.name.trim() !== '')) {
    const name = row.name.trim();
    if (!row.secret) {
      headers[name] = row.value;
      continue;
    }
    const kept = headerReference(row.value, headerSecretName(server, name));
    headers[name] = kept.sent;
    secrets[headerSecretName(server, name)] = kept.secret;
  }
  return { headers, secrets };
}

/** Why a remote server cannot be reached at this address, in the runtime's terms, or undefined when it can. */
export function remoteAddressProblem(url: string): string | undefined {
  let parsed: URL;
  try {
    parsed = new URL(url.trim());
  } catch {
    // A half typed address is the person's to finish, so it is said rather than thrown.
    return `${url.trim()} is not an address.`;
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return 'A remote server is reached over http or https.';
  if (parsed.protocol === 'http:' && !LOOPBACK_HOSTS.includes(parsed.hostname)) return 'Plain http is only for a server on this computer, at localhost or 127.0.0.1. Use https for one anywhere else.';
  return undefined;
}

/** A header as the inspector lists it, by name only, and whether the secret the Add server dialog named for it is held. */
export function headerLines(server: Pick<McpHubServerView, 'name' | 'headerNames' | 'secretsHeld'>): { name: string; held?: boolean }[] {
  return (server.headerNames ?? []).map((name) => {
    const held = server.secretsHeld[headerSecretName(server.name, name)];
    return held === undefined ? { name } : { name, held };
  });
}
