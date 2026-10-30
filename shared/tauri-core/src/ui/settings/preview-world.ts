import type { ActivityRow, AgentView, DaemonRequest, DaemonResponse, DeviceWire, HomeView, McpHubView, PolicyRulesView, ProgressView, SessionCard, VoiceAgentStatus } from '@memnox/core/wire';
import type { ConfirmKey } from '../../core/application/ports/confirm-key';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { PreferenceStore } from '../../core/application/ports/preference-store';
import type { Runtime } from '../../core/application/ports/runtime';
import { PREFERENCE } from '../../core/application/preferences';
import type { Platform } from '../../core/domain/platform';
import type { SettingsHost } from './host';
import type { Pairer } from '../../core/application/ports/pairer';
import type { HttpTransport, PersonCredentialStore } from '../../core/application/ports/workspace-inbox';
import { Base64URL } from '../../core/domain/base64url';
import type { PairedServer } from '../../core/domain/paired-machines';
import type { WorkspaceCredential } from '../../core/domain/workspace-wire';
import type { RelayAdapters, SettingsParts } from './parts';

/**
 * A computer and a daemon made of script, so every Settings page and first run step draws in a plain
 * browser: `pnpm dev`, then /settings.html?page=phones&state=digits&theme=dark. Nothing here reaches Tauri.
 */
const asked = new URLSearchParams(window.location.search);
/** Which variant of a page to draw, such as signed-in on Account or qr on Phones. */
export const previewState = asked.get('state') ?? '';
const platform: Platform = asked.get('platform') === 'linux' ? 'linux' : 'windows';

const agents: VoiceAgentStatus[] = [
  { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, works: true, chosen: true, install: '' },
  { kind: 'codex', label: 'Codex', installed: true, sealed: true, works: true, chosen: false, install: '' },
  { kind: 'cursor', label: 'Cursor', installed: true, sealed: false, works: false, because: 'its plan ran out', reply: 'You have reached your usage limit.', chosen: false, install: '' },
  { kind: 'hermes', label: 'Hermes', installed: false, sealed: true, chosen: false, install: 'pip install hermes' },
];

const home: HomeView = {
  machine: 'desk',
  mode: 'enforce',
  waiting: 2,
  working: [
    { sessionId: 's1', agent: 'claude-code', agentName: 'Claude Code', task: 'Port the Settings window', repository: 'memnox-desktop' },
    { sessionId: 's2', agent: 'codex', agentName: 'Codex', task: 'Fix the flaky relay test', repository: 'memnox-runtime' },
  ],
  today: { actions: 41, asked: 6, allowed: 5, refused: 1 },
  ready: { action: 'git push', approvals: 5, agentName: 'Codex', targets: ['origin feature/*'], because: 'Every push this week went to a feature branch and you allowed each one.' },
  notCovered: { unprotected: 1, dormant: 0 },
  needsYou: ['Approve the Memnox hooks in Codex, so its commands are checked.'],
};

/** A few sessions across two repositories, so Home, Agents and Workspaces have something to lay out. */
const previewSessions: SessionCard[] = [
  { sessionId: 's1', agent: 'claude-code', agentName: 'Claude Code', task: 'Port the Settings window', repository: '/code/memnox-desktop', state: 'working', thinking: false, lastActive: '2026-10-30T11:58:00Z', actions: 37 },
  { sessionId: 's2', agent: 'codex', agentName: 'Codex', task: 'Fix the flaky relay test', repository: '/code/memnox-runtime', state: 'open', thinking: false, lastActive: '2026-10-30T11:40:00Z', actions: 12 },
  { sessionId: 's3', agent: 'cursor', agentName: 'Cursor', task: 'Tidy the onboarding copy', repository: '/code/memnox-desktop', state: 'ended', thinking: false, lastActive: '2026-10-29T17:10:00Z', actions: 8 },
];

/** A hub with servers in each state, found ones to bring in, and one a person edited by hand. */
const previewHub: McpHubView = {
  servers: [
    { name: 'github', description: 'Issues and pull requests', transport: 'stdio', command: 'npx', args: ['-y', '@modelcontextprotocol/server-github'], envNames: [], scope: 'personal', governed: true, toolCount: 26, health: { state: 'healthy', checkedAt: '2026-10-30T11:50:00Z', tools: [{ name: 'create_pull_request', description: 'Open a pull request' }, { name: 'list_issues', description: 'List the issues of a repository' }] }, agents: ['claude-code', 'codex-cli'], secretsHeld: { 'github-token': true }, callsThisWeek: 48 },
    { name: 'postgres', description: 'The local development database', transport: 'stdio', command: 'npx', args: ['-y', '@modelcontextprotocol/server-postgres'], envNames: ['DATABASE_URL'], scope: 'personal', governed: true, toolCount: 0, health: { state: 'unknown' }, agents: ['claude-code'], secretsHeld: {}, callsThisWeek: 3 },
    { name: 'linear', transport: 'stdio', command: 'npx', args: ['-y', 'linear-mcp'], envNames: [], scope: 'personal', governed: true, toolCount: 0, health: { state: 'error', checkedAt: '2026-10-30T09:00:00Z', error: 'LINEAR_API_KEY is not set' }, agents: [], secretsHeld: { 'linear-api-key': false }, callsThisWeek: 0 },
    { name: 'docs', description: 'Company documentation', transport: 'http', url: 'https://mcp.example.com/docs', envNames: [], scope: 'organization', governed: false, toolCount: 4, health: { state: 'unknown' }, agents: ['cursor'], secretsHeld: {}, callsThisWeek: 11 },
  ],
  agents: [
    { agent: 'claude-code', path: '~/.claude.json' },
    { agent: 'codex-cli', path: '~/.codex/config.toml' },
    { agent: 'cursor', path: '~/.cursor/mcp.json' },
  ],
  found: [
    { agent: 'cursor', path: '~/.cursor/mcp.json', name: 'notion' },
    { path: '/code/memnox-runtime/.mcp.json', name: 'playwright' },
  ],
  drifted: [{ agent: 'codex-cli', path: '~/.codex/config.toml', name: 'postgres', kind: 'edited' }],
  skipped: [],
};

const previewRules: PolicyRulesView = {
  rules: [
    { name: 'git-deny', effect: 'deny', match: { actions: ['git.push-force', 'git.reset-hard'] }, sentence: 'Never force push or hard reset', reason: 'it rewrites history somebody may have pulled', source: 'default', editable: false },
    { name: 'shell-ask', effect: 'ask', match: { actions: ['filesystem.delete'] }, sentence: 'Ask before deleting files', source: 'file', file: 'memnox.policies.toml', editable: false },
    { name: 'push-main', effect: 'ask', match: { actions: ['git.push'], branches: ['main'] }, sentence: 'Ask before pushing to main', source: 'person', decidedBy: 'Sam', editable: true },
    { name: 'read-docs', effect: 'allow', match: { actions: ['mcp.search_docs'], agents: ['claude-code'] }, sentence: 'Let Claude Code search the docs without asking', source: 'autopilot', editable: false },
  ],
  problems: [],
  missing: [],
};

const previewProgress: ProgressView = {
  ready: [{ action: 'git.push', approvals: 7, targets: ['origin feature/*'], because: 'Every push this week went to a feature branch and you allowed each one.' }],
  almost: [{ action: 'npm.publish', approvals: 3, needed: 5 }],
  grants: [{ id: 'ern_1', actions: ['mcp.search_docs'], targets: [], agents: ['claude-code'], since: '2026-10-27T09:00:00Z', until: '2026-11-03T09:00:00Z', says: 'Claude Code searches the docs without asking' }],
  autopilotOn: true,
  ladder: { level: 'supervised', says: 'Routine work runs; anything outward or destructive is held.', rungs: ['observe', 'assist', 'supervised', 'autonomous', 'trusted'], next: 'autonomous', needs: '38 more actions this week before Autonomous can be claimed.', actionsThisWeek: 12, asksThisWeek: 4, minimumEvidence: 50 },
  thisWeek: { from: '2026-10-27', asked: 12, answeredByAutopilot: 9, handedOver: 1 },
  lastWeek: { from: '2026-10-20', asked: 31, answeredByAutopilot: 2, handedOver: 0 },
};

const previewActivity: ActivityRow[] = [
  { id: 'e1', at: '2026-10-30T11:58:00Z', agent: 'claude-code', agentName: 'Claude Code', session: 's1', kind: 'command', operation: 'git.push', target: 'origin main', effect: 'ask', rule: 'push-main', reason: 'you chose to be asked before anything reaches main', answeredBy: 'Sam', answeredHow: 'signed' },
  { id: 'e2', at: '2026-10-30T11:50:00Z', agent: 'codex', agentName: 'Codex', session: 's2', kind: 'file', operation: 'filesystem.delete', target: 'build/', effect: 'ask', rule: 'shell-ask', reason: 'sometimes it really is the build directory' },
  { id: 'e3', at: '2026-10-30T11:41:00Z', agent: 'claude-code', agentName: 'Claude Code', session: 's1', kind: 'mcp', operation: 'mcp.create_pull_request', target: 'github', effect: 'allow', reason: 'no rule held it' },
  { id: 'e4', at: '2026-10-30T11:30:00Z', agent: 'codex', agentName: 'Codex', session: 's2', kind: 'command', operation: 'git.push-force', target: 'origin main', effect: 'deny', rule: 'git-deny', reason: 'it rewrites history somebody may have pulled' },
];

const previewAgents: AgentView[] = [
  { kind: 'claude-code', name: 'Claude Code', status: 'protected', sessions: { running: 1, idle: 2, finished: 14 }, mcpServers: ['github', 'postgres'], today: { actions: 37, asked: 3, refused: 0 }, recent: [{ id: 'e1', at: '2026-10-30T11:58:00Z', operation: 'git.push', target: 'origin main', effect: 'ask' }] },
  { kind: 'codex-cli', name: 'Codex', status: 'protected', sessions: { running: 0, idle: 1, finished: 6 }, mcpServers: ['github'], today: { actions: 12, asked: 2, refused: 1 }, recent: [{ id: 'e4', at: '2026-10-30T11:30:00Z', operation: 'git.push-force', target: 'origin main', effect: 'deny' }] },
  { kind: 'cursor', name: 'Cursor', status: 'unprotected', sessions: { running: 0, idle: 0, finished: 2 }, mcpServers: ['docs'], today: { actions: 0, asked: 0, refused: 0 }, recent: [] },
];

const phones: DeviceWire[] = [{ id: 'dev_1', name: 'Sam’s iPhone', kind: 'phone', fingerprint: 'fp', capabilities: ['see', 'ask', 'answer', 'mac'], pairedAt: '2026-10-01T10:00:00Z' }];

const qr =
  'memnox://pair?d=eyJ2IjoxLCJtYWNoaW5lSWQiOiJtX2Rlc2siLCJtYWNoaW5lIjoiRGVzayIsInJlbGF5VXJsIjoid3NzOi8vcmVsYXkubWVtbm94LmNvbSIsIm1haWxib3giOiJhYmNkZWYiLCJwYWlyaW5nVG9rZW4iOiJybHBfMTIzIn0';

/** Every method a page asks, answered from the scene. */
/** Methods no runtime answers yet, so the preview hides the tabs that read them, as the app does. */
const NOT_YET: readonly string[] = ['skills-hub', 'memory-learn'];

function answer(request: DaemonRequest): DaemonResponse[] {
  const ok = { id: request.id, ok: true };
  if (NOT_YET.includes(request.method)) return [{ id: request.id, ok: false, error: `no method ${request.method}` }];
  if (request.method.startsWith('mcp-')) return [{ ...ok, mcpHub: previewHub, ...(request.method === 'mcp-assign' && request.mcpOn === true ? { proposed: 'prp_preview' } : {}) }];
  if (request.method === 'rules' || request.method === 'rule-remove') return [{ ...ok, policyRules: previewRules }];
  if (request.method === 'progress') return [{ ...ok, progress: previewProgress }];
  if (request.method === 'rule-propose' || request.method === 'agent-resume') return [{ ...ok, proposed: 'prp_preview' }];
  if (request.method === 'rule-test') return [{ ...ok, ruleVerdict: { effect: 'ask', reason: 'you chose to be asked before anything reaches main', rule: 'push-main' } }];
  if (request.method === 'activity') return [{ ...ok, activity: { rows: previewActivity } }];
  if (request.method === 'decision') {
    const row = previewActivity.find((each) => each.id === request.decisionId) ?? previewActivity[0];
    return row === undefined ? [ok] : [{ ...ok, decision: { row, ...(row.rule === undefined ? {} : { rule: { name: row.rule, source: 'person', decidedBy: 'Sam' } }), chain: 'Claude Code for Sam', context: [], before: [], trace: { mode: 'shell', exitCode: 0 } } }];
  }
  if (request.method.startsWith('agent') || request.method === 'session-stop') return [{ ...ok, agentsView: previewAgents }];
  switch (request.method) {
    case 'ping':
      return [{ ...ok, version: '0.20.0' }];
    case 'register-key':
      return [{ ...ok, outcome: previewState === 'key-missing' ? 'another key' : 'registered' }];
    case 'voice-agents':
    case 'choose-voice-agent':
      return [{ ...ok, voiceAgents: agents }];
    case 'home':
      return previewState === 'no-home' ? [{ id: request.id, ok: false, error: 'no method home' }] : [{ ...ok, home }];
    case 'waiting':
      return [{ ...ok, waiting: [] }];
    case 'sessions-list':
      return [{ ...ok, sessions: previewSessions }];
    case 'person':
      return [{ ...ok, person: previewState === 'signed-in' ? { signedIn: true, name: 'Sam Rivera' } : { signedIn: false, ...(previewState === 'code' ? { code: { userCode: 'WDJB-MJHT', expiresAt: Date.now() + 600_000 } } : {}) } }];
    case 'machine':
      return [{ ...ok, machine: previewState === 'code' || previewState === 'signed-out' ? { signedIn: false } : { signedIn: true, name: 'Acme' } }];
    case 'person-sign-in':
      return [{ ...ok, person: { signedIn: false, code: { userCode: 'WDJB-MJHT', expiresAt: Date.now() + 600_000 } } }];
    case 'connections-list':
      return [{ ...ok, connections: [{ toolkit: 'github', connected: true }, { toolkit: 'slack', connected: true }, { toolkit: 'gmail', connected: false }] }];
    case 'toolkits-search':
      return [{ ...ok, toolkits: [{ slug: 'notion', name: 'Notion' }, { slug: 'linear', name: 'Linear' }, { slug: 'googledocs', name: 'Google Docs' }] }];
    case 'connections-sign-in':
      return [{ ...ok, signIn: { toolkit: request.toolkit ?? '', url: 'https://connect.composio.dev/preview', opened: true } }];
    case 'connections-sign-out':
      return [{ ...ok, connections: [{ toolkit: 'github', connected: true }] }];
    case 'devices-list':
      return [{ ...ok, devices: previewState === 'none' ? [] : phones }];
    case 'pair-begin':
      return [{ ...ok, outcome: 'pairing', pairing: { id: 'pr_1', qr, state: 'waiting' } }];
    case 'pair-pending':
      return previewState === 'digits' ? [{ ...ok, pairing: { id: 'pr_1', state: 'answered', phone: { name: 'iPhone', fingerprint: 'fp', code: '482913' } } }] : [];
    default:
      return [ok];
  }
}

export const previewLink: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    yield* answer(request);
    // A pairing still waiting stays open, as the daemon keeps it.
    if (request.method === 'pair-pending') await new Promise<never>(() => undefined);
  },
};

export const previewRuntime: Runtime = {
  found: async () => true,
  install: async () => true,
  wired: async () => true,
  run: async () => true,
};

export const previewKey: ConfirmKey = {
  publicPoint: async () => 'BPOINT',
  sign: async (message) => `sig(${message})`,
};

/** A store in memory, seeded so the overview shows a person part way through setup. */
export class PreviewStore implements PreferenceStore {
  private readonly kept = new Map<string, string>();

  constructor(seed: Record<string, string>) {
    for (const [key, value] of Object.entries(seed)) this.kept.set(key, value);
  }

  load(key: string): string | null {
    return this.kept.get(key) ?? null;
  }

  save(key: string, value: string): void {
    if (value === '') this.kept.delete(key);
    else this.kept.set(key, value);
    window.dispatchEvent(new CustomEvent('memnox-preference', { detail: key }));
  }
}

export function previewSeed(): Record<string, string> {
  const look = asked.get('theme');
  const seed: Record<string, string> = { [PREFERENCE.name]: 'Sam Rivera', [PREFERENCE.firstRun]: 'mac' };
  if (look === 'light' || look === 'dark') seed[PREFERENCE.appearance] = look;
  if (previewState === 'firstrun') {
    delete seed[PREFERENCE.firstRun];
    delete seed[PREFERENCE.name];
  }
  if (previewState === 'home') seed[PREFERENCE.setupDone] = 'true';
  if (previewState === 'dictation') {
    seed['memnox.dictation.words'] = JSON.stringify([{ said: 'orb', written: 'ORB' }, { written: 'Memnox' }]);
    seed['memnox.dictation.history'] = JSON.stringify([
      { written: 'Can you rerun the relay tests and tell me which one flakes?', app: 'Slack', at: Date.parse('2026-10-18T09:41:00') },
      { written: 'Ship it once the build is green.', at: Date.parse('2026-10-18T09:12:00') },
    ]);
  }
  return seed;
}

export const previewHost: SettingsHost = {
  platform,
  computerName: () => 'Desk',
  permissionFacts: async () => {
    // An editor here, and the extension landed except in the state that shows what still needs doing.
    const editors = { present: true, withExtension: previewState === 'needs' ? [] : ['.vscode/extensions'] };
    return platform === 'linux'
      ? { platform, session: 'wayland', microphone: 'allowed', typing: previewState !== 'needs', editors, polkitAgent: previewState !== 'needs', seeing: { portal: true, accessibility: true } }
      : { platform, session: 'desktop', microphone: previewState === 'needs' ? 'denied' : 'allowed', typing: true, editors };
  },
  openPrivacy: async () => true,
  startsAtSignIn: async () => previewState !== 'needs',
  setStartsAtSignIn: async (on) => on,
  restart: () => undefined,
  openPage: () => undefined,
  openSettings: () => undefined,
  openOnboarding: () => undefined,
  close: () => undefined,
  applyLook: () => undefined,
  talk: () => undefined,
  copy: async () => undefined,
  onShowPage: () => () => undefined,
  voices: {
    choice: async () => ({ speed: 0.85, voices: ['system', 'af_sky', 'af_heart', 'af_bella', 'af_nicole', 'af_sarah', 'am_adam', 'am_michael', 'bf_emma', 'bf_isabella', 'bm_george', 'bm_lewis'], chosen: 'af_heart' }),
    choose: async () => undefined,
    setSpeed: async () => undefined,
    installed: async () => previewState !== 'installing',
    install: () => new Promise<void>(() => undefined),
    say: async () => undefined,
    test: async () => undefined,
  },
};

/** A server kept in the scene, and one more the person can pair with. */
const keptServers: PairedServer[] = [{ machineId: 'm_box', machine: 'build-box', deviceId: 'dev_desk', pairedAt: 1 }];
const servers = (): PairedServer[] => (previewState === 'servers' || previewState === 'server-code' ? keptServers : []);
const never = new Promise<never>(() => undefined);

const previewPairer: Pairer = {
  async pair(_link, _name, code) {
    code('482913');
    return never;
  },
  servers: async () => servers(),
  forget: async () => undefined,
};

const signedIn: WorkspaceCredential = { token: 'tok', tokenId: 'tk', personId: 'p', name: 'Sam Rivera', orgId: 'o', workspaces: ['ws_1'], deviceId: 'dev_1' };

const previewCloud: HttpTransport = {
  async send(method, path) {
    if (method === 'POST' && path === 'v1/person/codes') return { status: 200, body: JSON.stringify({ deviceCode: 'dc', userCode: 'WDJB-MJHT', intervalSeconds: 5, expiresAt: Date.now() + 600_000 }) };
    if (path === 'v1/person/tokens') return never;
    return { status: 404, body: '{}' };
  },
};

const previewCredentials: PersonCredentialStore = {
  load: async () => (previewState === 'team' ? signedIn : undefined),
  save: async () => undefined,
  delete: async () => undefined,
};

export const previewRelay: RelayAdapters = { pairer: previewPairer, cloud: previewCloud, credentials: previewCredentials };

/** A pairing link the scene pastes for itself, good for the next two minutes. */
function previewLinkToPaste(): string {
  const key = Base64URL.encode(new Uint8Array(32).fill(7)).replace(/-/g, '+').replace(/_/g, '/') + '=';
  const wire = { v: 1, machineId: 'm_gpu', machine: 'gpu-box', relayUrl: 'wss://relay.memnox.com/v1/relay', mailbox: Base64URL.encode(new Uint8Array(16).fill(1)), pairingToken: 'rlp_1', runtimeNoiseStatic: key, secret: key, expiresAt: new Date(Date.now() + 120_000).toISOString() };
  return `memnox://pair?d=${Base64URL.encode(new TextEncoder().encode(JSON.stringify(wire)))}`;
}

/** Puts the scene where its state asks, since a screenshot cannot press Connect or Sign in. */
export function previewKickoff(parts: SettingsParts): void {
  if (previewState === 'server-code') void parts.servers.load().then(() => parts.servers.connect(previewLinkToPaste()));
  if (previewState === 'server-failed') void parts.servers.connect('https://example.com/not-a-link');
  if (previewState === 'team-code') void parts.team.start();
}
