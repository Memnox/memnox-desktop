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
export const PROJECT_ONLY_LINE = "A folder means the agent has this server only in that project. It is given in that project's settings, so it is changed in Projects, and giving it here gives it in every project.";
/** The control beside a project only assignment: it gives the server everywhere, signed like every other give. */
export const GIVE_EVERYWHERE = 'Give in every project';
export const WORKSPACES_LINK = 'Open Projects';

/** The help on a project only cell: who has it, where, and where it is changed. */
export function projectOnlyHelp(server: Pick<McpHubServerView, 'projects'>, agent: string): string {
  const paths = projectsFor(server, agent).map((each) => each.path);
  return `${agentLabel(agent)} has this server only in ${paths.join(', ')}, given in that project's settings in Projects.`;
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

/** An address's scheme and host, read without the browser's URL, which the core is built without. */
const ADDRESS = /^([a-z][a-z0-9+.-]*):\/\/(\[[^\]/]*\]|[^/:?#@\s]+)(?::\d+)?(?:[/?#]\S*)?$/i;

/** Why a remote server cannot be reached at this address, in the runtime's terms, or undefined when it can. */
export function remoteAddressProblem(url: string): string | undefined {
  const parsed = ADDRESS.exec(url.trim());
  if (parsed === null) return `${url.trim()} is not an address.`;
  const scheme = (parsed[1] ?? '').toLowerCase();
  const host = (parsed[2] ?? '').toLowerCase();
  if (scheme !== 'http' && scheme !== 'https') return 'A remote server is reached over http or https.';
  if (scheme === 'http' && !LOOPBACK_HOSTS.includes(host)) return 'Plain http is only for a server on this computer, at localhost or 127.0.0.1. Use https for one anywhere else.';
  return undefined;
}

/** A header as the inspector lists it, by name only, and whether the secret the Add server dialog named for it is held. */
export function headerLines(server: Pick<McpHubServerView, 'name' | 'headerNames' | 'secretsHeld'>): { name: string; held?: boolean }[] {
  return (server.headerNames ?? []).map((name) => {
    const held = server.secretsHeld[headerSecretName(server.name, name)];
    return held === undefined ? { name } : { name, held };
  });
}

/** "Remote" or "Local", the pill beside a server's name. */
export function transportWord(server: Pick<McpHubServerView, 'transport'>): string {
  return server.transport === 'http' ? 'Remote' : 'Local';
}

/** Each agent a server is given to, once, in the order the hub lists them. */
export function agentsOnce(server: Pick<McpHubServerView, 'agents'>): string[] {
  return [...new Set(server.agents)];
}

/** Which agents use a server, by name: "Claude Code and Cursor", or that none was given it yet. */
export function usedBy(server: Pick<McpHubServerView, 'agents'>): string {
  const names = agentsOnce(server).map(agentLabel);
  const last = names[names.length - 1];
  if (last === undefined) return agentsLine(0);
  if (names.length === 1) return last;
  return `${names.slice(0, -1).join(', ')} and ${last}`;
}

/** What a row waiting on the island says before the runtime's own words about it. */
export function waitingForKey(keyTitle: string): string {
  return `Waiting for ${keyTitle} on the island`;
}

/** The line one row says about its last press, and its tone; nothing while the runtime still works on it. */
export function pressLine(press: { kind: 'working' } | { kind: 'waiting'; note: string | undefined } | { kind: 'done'; line: string } | { kind: 'failed'; why: string } | undefined, keyTitle: string): { text: string; tone: 'good' | 'bad' | 'quiet' } | undefined {
  if (press === undefined) return undefined;
  switch (press.kind) {
    case 'working':
      return undefined;
    case 'waiting':
      return { text: [waitingForKey(keyTitle), press.note].filter((part): part is string => part !== undefined && part !== '').join('. '), tone: 'quiet' };
    case 'done':
      return { text: press.line, tone: 'good' };
    case 'failed':
      return { text: press.why, tone: 'bad' };
  }
}

/** What the page says after a server is added, as the Mac's `McpHubLines.added`: who it waits on, what will run, and who is asked next. */
export function addedLine(press: Parameters<typeof pressLine>[0], server: string, agents: readonly string[], keyTitle: string): string | undefined {
  if (press?.kind !== 'waiting') return pressLine(press, keyTitle)?.text;
  const parts = [`${server} waits for ${keyTitle} on the island`];
  if (press.note !== undefined && press.note !== '') parts.push(press.note.endsWith('.') ? press.note.slice(0, -1) : press.note);
  const names = agents.map(agentLabel);
  const last = names.at(-1);
  if (last !== undefined) {
    const who = names.length === 1 ? last : `${names.slice(0, -1).join(', ')} and ${last}`;
    parts.push(`Once it is signed, giving it to ${who} asks for ${keyTitle} again`);
  }
  return `${parts.join('. ')}.`;
}

/** Under the Command field, as the Mac's Add a server sheet says it. */
export const COMMAND_HINT = 'The command that starts it. An install such as pip install or npm install is fine too: Memnox starts it with the runner that installs it.';

/** A found server's button while it is brought in, and before. */
export const BRING_IN = 'Bring into the hub';
export const BRINGING_IN = 'Bringing in';

/** The narrowest a server card reads well at, the Mac's `McpServersLayout.cardWidth`. */
export const SERVER_CARD_MIN = 300;

/** The Add a server sheet's words, step by step. */
export const AddServerLines = {
  title: 'Add a server',
  steps: ['Server', 'Variables', 'Agents'] as const,
  stepOf: (step: string, at: number, of: number) => `${step} · step ${at} of ${of}`,
  name: 'Name',
  namePlaceholder: 'github',
  description: 'What it is for, optional',
  descriptionPlaceholder: 'Issues and pull requests',
  howItRuns: 'How it runs',
  local: 'On this computer',
  localBody: 'Started by a command',
  remote: 'Remote',
  remoteBody: 'Reached at an address',
  address: 'Address',
  addressPlaceholder: 'https://mcp.example.com/mcp',
  command: 'Command',
  commandPlaceholder: 'npx -y @modelcontextprotocol/server-github',
  remoteNote: 'Memnox stands in front of a remote server, so every call to it is ruled on and recorded. Plain http is only for one on this computer.',
  secretNote: "Mark a token or key as secret: this computer keeps it, and agents' configs only name it.",
  variableName: 'Variable name',
  variablePlaceholder: 'GITHUB_TOKEN',
  value: 'Value',
  secret: 'Secret',
  removeVariable: 'Remove this variable',
  addVariable: 'Add a variable',
  chooseAgents: (keyTitle: string) => `Choose who gets it. Each one waits for your signature with ${keyTitle}.`,
  noAgents: 'No agent with an MCP config was found yet. The server is kept, and you can give it later.',
  hideWritten: 'Hide what will be written',
  showWritten: 'Show what will be written',
  back: 'Back',
  continue: 'Continue',
  add: 'Add server',
  needsName: 'Give the server a name.',
  needsAddress: 'Give the address the server answers on.',
  needsCommand: 'Give the command that starts the server.',
  headers: 'Headers, optional',
  headerName: 'Header name',
  headerPlaceholder: 'Authorization',
  headerValue: 'Header value',
  headerValuePlaceholder: 'Bearer your token',
  keepSecret: 'Keep as secret',
  credentialHeader: 'This header carries a credential, so it is always kept as a secret.',
  removeHeader: 'Remove this header',
  addHeader: 'Add a header',
} as const;

/** The MCP Hub page's own words. */
export const McpHubPageLines = {
  readWhat: 'the MCP Hub',
  waiting: (keyTitle: string) => `Waiting for you on the island: confirm it with ${keyTitle} and the runtime writes it.`,
  search: 'Search servers',
  syncHelp: 'Write what the hub gives each agent into its config again',
  sync: 'Sync',
  add: 'Add server',
  emptyTitle: 'No servers in the hub yet',
  emptyBody: 'Add a server once and give it to any agent, or bring in one an agent already has from Found on this computer below.',
  needsSecret: 'Needs a secret',
  testHelp: 'Starts the server once and asks what it offers',
  testing: 'Testing',
  test: 'Test',
  governed: 'Governed',
  notGoverned: 'Not governed',
  asking: 'Asking the runtime',
  needs: (names: readonly string[]) => `Needs ${names.join(', ')}`,
  tested: (when: string | undefined) => `Tested ${when ?? 'just now'}`,
  testConnection: 'Test connection',
  agents: 'Agents',
  takeAway: 'Take away',
  give: 'Give',
  givingWaits: (keyTitle: string) => `Giving a server to an agent waits for your signature with ${keyTitle}. Taking it away happens at once.`,
  headers: 'Headers',
  secretKept: 'Secret kept by this computer',
  secretNotSet: 'Secret not set',
  headersNote: 'Sent with every call to the server. Only the names are shown here, never the values.',
  credentials: 'Credentials',
  keptHere: 'Kept by this computer',
  notSet: 'Not set',
  credentialsNote: 'A secret is never shown again. Replace one under Secrets.',
  tools: 'Tools',
  noTools: 'Test the connection to list what this server can do.',
  removeEverywhere: 'Remove from every agent',
  found: (count: number) => `Found on this computer · ${count}`,
  shared: 'Shared by several agents',
  repositoryFile: 'A repository’s own file',
  bringingNote: 'Bringing a server in puts it behind Memnox, so every call it makes is ruled on and recorded.',
  leftAlone: 'Left as they are',
  removedLine: 'You removed the line the hub wrote, so it is not put back.',
  changedLine: 'You changed the line the hub wrote, so the hub leaves it alone.',
  yoursNow: 'Yours now',
  secretsTitle: 'Secrets',
  valueOf: (name: string) => `The value of ${name}`,
  keep: 'Keep',
  kept: 'Kept',
  replace: 'Replace',
  set: 'Set',
  remove: 'Remove',
  usedBy: (names: readonly string[]) => `Used by ${names.join(', ')}`,
} as const;
