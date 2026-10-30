import type { ActivityRow, AgentView, BackupSummary, CommunityIndexView, DaemonRequest, DaemonResponse, DeviceWire, HomeView, LanStatus, McpHubView, MemoryItemView, MemorySourceView, PersonalSyncConflict, PersonalSyncStatus, PolicyRulesView, ProfileView, ProgressView, ProjectView, RulePackView, SessionCard, SkillsHubView, VoiceAgentStatus } from '@memnox/core/wire';
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
    { name: 'desktop-release', effect: 'ask', match: { actions: ['npm.publish'], workingDirectories: ['/code/memnox-desktop'] }, sentence: 'Ask before publishing the desktop packages', source: 'file', file: '/code/memnox-desktop/.memnox/policies.toml', editable: false },
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
  { kind: 'claude-code', name: 'Claude Code', status: 'protected', sessions: { running: 1, idle: 2, finished: 14 }, mcpServers: ['github', 'postgres'], skills: ['release-notes', 'review-checklist'], launchable: true, today: { actions: 37, asked: 3, refused: 0 }, recent: [{ id: 'e1', at: '2026-10-30T11:58:00Z', operation: 'git.push', target: 'origin main', effect: 'ask' }] },
  { kind: 'codex-cli', name: 'Codex', status: 'protected', sessions: { running: 0, idle: 1, finished: 6 }, mcpServers: ['github'], skills: ['review-checklist'], launchable: true, today: { actions: 12, asked: 2, refused: 1 }, recent: [{ id: 'e4', at: '2026-10-30T11:30:00Z', operation: 'git.push-force', target: 'origin main', effect: 'deny' }] },
  { kind: 'cursor', name: 'Cursor', status: 'unprotected', sessions: { running: 0, idle: 0, finished: 2 }, mcpServers: ['docs'], skills: [], launchable: false, today: { actions: 0, asked: 0, refused: 0 }, recent: [] },
];

/** Skills in each standing: one in use, one held for reaching further, one off, and two found to bring in. */
const previewSkills: SkillsHubView = {
  skills: [
    {
      name: 'release-notes',
      scope: 'personal',
      category: 'Writing',
      version: '1.2.0',
      description: 'Drafts release notes from the pull requests merged since the last tag',
      publisher: 'Sam Rivera',
      enabled: true,
      digest: 'sha256:5f1c0a9e2b7d4c3a8e6f1b2d9c0a7e4f3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e',
      agents: ['claude-code', 'codex-cli'],
      assignments: [{ agent: 'claude-code' }, { agent: 'codex-cli' }],
      compatibility: [
        { agent: 'claude-code', label: 'Claude Code', supported: true, loses: [] },
        { agent: 'codex-cli', label: 'Codex', supported: true, loses: ['Its tool grant, since Codex reads instructions only'] },
        { agent: 'cursor', label: 'Cursor', supported: true, loses: ['Its tool grant, since a Cursor rule carries none', 'The files beside the instructions'] },
      ],
      versions: [
        { version: '1.0.0', current: false, acceptedAt: '2026-09-02T10:00:00Z' },
        { version: '1.1.0', current: false, acceptedAt: '2026-10-01T10:00:00Z' },
        { version: '1.2.0', current: true, acceptedAt: '2026-10-26T10:00:00Z' },
      ],
      updatedAt: '2026-10-26T10:00:00Z',
      files: ['template.md', 'examples/0.19.md'],
      instructions: '# Release notes\n\n1. List the pull requests merged since the last tag with gh.\n2. Group them by area.\n3. Write one line each, in the past tense, and link the pull request.',
      tools: ['Read', 'Bash'],
      mcpServers: ['github'],
      permissions: { filesystem: [], network: ['api.github.com'], commands: ['gh', 'git'] },
      dependencies: [],
    },
    {
      name: 'review-checklist',
      scope: 'project',
      project: '/code/memnox-desktop',
      category: 'Review',
      version: '0.3.0',
      description: 'Checks a change against the repository conventions before it is pushed',
      enabled: true,
      digest: 'sha256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b',
      held: { standing: 'widened', gained: ['Bash', 'curl'], signed: true },
      agents: ['claude-code', 'codex-cli'],
      assignments: [{ agent: 'claude-code', project: '/code/memnox-desktop' }, { agent: 'codex-cli', project: '/code/memnox-desktop' }],
      compatibility: [
        { agent: 'claude-code', label: 'Claude Code', supported: true, loses: [] },
        { agent: 'codex-cli', label: 'Codex', supported: true, loses: [] },
        { agent: 'cursor', label: 'Cursor', supported: true, loses: [] },
      ],
      versions: [{ version: '0.2.0', current: false, acceptedAt: '2026-10-10T10:00:00Z' }, { version: '0.3.0', current: true }],
      updatedAt: '2026-10-29T15:00:00Z',
      files: [],
      instructions: 'Read CLAUDE.md, then check every changed line against it.',
      tools: ['Read', 'Bash'],
      mcpServers: [],
      permissions: { filesystem: [], network: [], commands: ['curl'] },
      dependencies: ['release-notes'],
    },
    {
      name: 'triage',
      scope: 'personal',
      version: '1.0.0',
      description: 'Labels new issues and asks for what is missing',
      enabled: false,
      digest: 'sha256:1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c',
      agents: [],
      assignments: [],
      compatibility: [{ agent: 'claude-code', label: 'Claude Code', supported: true, loses: [] }],
      versions: [{ version: '1.0.0', current: true, acceptedAt: '2026-08-14T10:00:00Z' }],
      updatedAt: '2026-08-14T10:00:00Z',
      files: [],
      instructions: 'Read the issue, label it, and ask the author for steps to reproduce when there are none.',
      tools: [],
      mcpServers: ['github'],
      permissions: { filesystem: [], network: [], commands: [] },
      dependencies: [],
    },
  ],
  found: [
    { id: 'f1', name: 'frontend-design', agent: 'claude-code', kind: 'skill', path: '~/.claude/skills/frontend-design', tools: ['Read', 'Write'], grant: 'reads and writes files', imported: false },
    { id: 'f2', name: 'security-review', agent: 'cursor', kind: 'skill', path: '~/.cursor/rules/security-review.mdc', tools: [], grant: 'no tools of its own', imported: false },
  ],
  agents: [
    { agent: 'claude-code', label: 'Claude Code', installed: true },
    { agent: 'codex-cli', label: 'Codex', installed: true },
    { agent: 'cursor', label: 'Cursor', installed: true },
    { agent: 'gemini-cli', label: 'Gemini CLI', installed: false },
  ],
};

/** One project saved and opened with its rules in force, and one only found, so Save as project shows. */
const previewProjects: ProjectView[] = [
  {
    id: 'prj_desktop',
    name: 'memnox-desktop',
    path: '/code/memnox-desktop',
    declared: true,
    opened: true,
    agents: ['claude-code', 'codex-cli'],
    agentsSeen: ['claude-code', 'cursor'],
    sessions: { total: 9, ended: 7 },
    servers: [
      { name: 'github', inHub: true, agents: ['claude-code', 'codex-cli'] },
      { name: 'figma', inHub: false, agents: [] },
    ],
    skills: [{ name: 'review-checklist', inHub: true, agents: ['claude-code', 'codex-cli'] }],
    rules: { file: '.memnox/policies.toml', count: 1, inForce: true },
    instructions: [
      { path: 'CLAUDE.md', source: true, present: true, agents: ['claude-code'], written: true },
      { path: 'AGENTS.md', source: false, present: true, agents: ['codex-cli'], written: true },
    ],
    memoryScope: 'project',
    openMissions: [{ id: 'msn_1', statement: 'Bring the Windows and Linux screens level with the Mac', startedAt: '2026-10-28T09:00:00Z' }],
    openQuestions: 2,
    lastActive: '2026-10-30T11:58:00Z',
    appliedAt: '2026-10-29T08:00:00Z',
  },
  {
    id: 'prj_runtime',
    name: 'memnox-runtime',
    path: '/code/memnox-runtime',
    declared: false,
    opened: false,
    agents: ['codex-cli'],
    agentsSeen: ['codex-cli'],
    sessions: { total: 3, ended: 2 },
    servers: [{ name: 'playwright', inHub: false, agents: [] }],
    skills: [],
    rules: { count: 0, inForce: false },
    instructions: [{ path: 'AGENTS.md', source: true, present: true, agents: ['codex-cli'], written: false }],
    memoryScope: 'project',
    openMissions: [],
    openQuestions: 0,
    lastActive: '2026-10-30T11:40:00Z',
  },
  {
    id: 'prj_api',
    scope: 'organization',
    organization: {
      id: 'op_api',
      name: 'Acme API',
      repository: 'github.com/acme/api',
      description: 'The public API and its workers',
      servers: ['github', 'docs'],
      skills: ['review-checklist'],
      rulePack: 'Release rules',
      rules: 4,
      memory: 'project',
      skipped: ['The skill api-style is not in the bundle this computer holds, so it was left out.'],
      editedIn: 'Acme API is the organization’s project, so it is changed in Memnox Cloud rather than here.',
    },
    name: 'Acme API',
    path: '/code/api',
    declared: true,
    opened: true,
    agents: ['claude-code'],
    agentsSeen: ['claude-code'],
    sessions: { total: 2, ended: 2 },
    servers: [{ name: 'github', inHub: true, agents: ['claude-code'] }],
    skills: [{ name: 'review-checklist', inHub: true, agents: ['claude-code'] }],
    rules: { count: 0, inForce: false },
    instructions: [],
    memoryScope: 'project',
    openMissions: [],
    openQuestions: 0,
    lastActive: '2026-10-29T15:00:00Z',
  },
];

const previewBackup: BackupSummary = { createdAt: '2026-10-30T12:00:00.000Z', files: ['policies.toml', 'mcp-hub.json', 'skills/release-notes/SKILL.md', 'projects.json'], ledger: false };

/** The packs Memnox ships, as the boundaries step lists them. */
const previewPacks: RulePackView[] = [
  { id: 'careful', name: 'Careful', description: 'Asks before anything leaves this computer or rewrites history.', ruleCount: 6, toml: '[[policies]]' },
  { id: 'balanced', name: 'Balanced', description: 'Lets routine work run and asks before pushes to main, deploys and deletes.', ruleCount: 4, toml: '[[policies]]' },
  { id: 'open', name: 'Open', description: 'Refuses only what cannot be undone, and records everything else.', ruleCount: 2, toml: '[[policies]]' },
];

const phones: DeviceWire[] = [{ id: 'dev_1', name: 'Sam’s iPhone', kind: 'phone', fingerprint: 'fp', capabilities: ['see', 'ask', 'answer', 'mac'], pairedAt: '2026-10-01T10:00:00Z' }];

const qr =
  'memnox://pair?d=eyJ2IjoxLCJtYWNoaW5lSWQiOiJtX2Rlc2siLCJtYWNoaW5lIjoiRGVzayIsInJlbGF5VXJsIjoid3NzOi8vcmVsYXkubWVtbm94LmNvbSIsIm1haWxib3giOiJhYmNkZWYiLCJwYWlyaW5nVG9rZW4iOiJybHBfMTIzIn0';

/** Three sources: a vault of the person's own, a Notion export read as untrusted, and Supermemory with no key. */
const previewMemorySources: MemorySourceView[] = [
  { id: 'src_vault', kind: 'obsidian', name: 'Vault', location: '/home/sam/vault', trust: 'trusted', scope: 'personal', watched: true, lastReadAt: '2026-10-30T11:20:00Z', counts: { candidate: 2, verified: 5, conflicting: 1, outdated: 1, rejected: 0 } },
  { id: 'src_notion', kind: 'notion-export', name: 'Team wiki', location: '/home/sam/Downloads/notion-export', trust: 'tainted', scope: 'project', project: '/code/memnox-desktop', watched: true, lastReadAt: '2026-10-29T16:00:00Z', lastError: 'Export-2a1f.zip is still zipped, so it was skipped', counts: { candidate: 1, verified: 0, conflicting: 0, outdated: 0, rejected: 2 } },
  { id: 'src_super', kind: 'supermemory', name: 'Supermemory', location: 'https://api.supermemory.ai', trust: 'tainted', scope: 'personal', watched: false, keyHeld: false, counts: { candidate: 0, verified: 0, conflicting: 0, outdated: 0, rejected: 0 } },
];

const vaultEvidence = (document: string, heading: string, stale = false) => ({ ref: `${document}#${heading}`, document, heading, source: 'Vault', stale });

/** The queue and the facts, statements kept exactly as written, a stale passage and a rule among them. */
const previewMemory: MemoryItemView[] = [
  { id: 'mem_1', kind: 'fact', statement: 'Releases ship on Tuesdays, never on a Friday.', subject: 'releases', status: 'verified', scope: 'personal', origin: 'extracted', tainted: false, extractorConfidence: 0.91, evidence: [vaultEvidence('ops/releases.md', 'Cadence'), vaultEvidence('ops/old-releases.md', 'Cadence', true)], createdAt: '2026-10-20T09:00:00Z', decidedAt: '2026-10-21T09:00:00Z', decidedBy: 'Sam Rivera' },
  { id: 'mem_2', kind: 'convention', statement: 'Commit messages are one line with a conventional prefix.', subject: 'commits', status: 'verified', scope: 'project', project: '/code/memnox-desktop', origin: 'agent', suggestedBy: 'claude-code', tainted: false, evidence: [], createdAt: '2026-10-22T09:00:00Z', decidedAt: '2026-10-22T10:00:00Z', decidedBy: 'Sam Rivera' },
  { id: 'mem_3', kind: 'rule', statement: 'Never push straight to main; open a pull request instead.', subject: 'git', status: 'candidate', scope: 'personal', origin: 'extracted', tainted: false, extractorConfidence: 0.78, rule: { effect: 'ask', actions: ['git.push'], targets: ['main'], reason: 'main is protected', sentence: 'Ask before any agent pushes to main.' }, evidence: [vaultEvidence('eng/git.md', 'Branches')], createdAt: '2026-10-28T08:00:00Z' },
  { id: 'mem_4', kind: 'fact', statement: 'The staging database is reset every night at 02:00 UTC.', subject: 'staging', status: 'candidate', scope: 'project', project: '/code/memnox-desktop', origin: 'extracted', tainted: true, extractorConfidence: 0.64, evidence: [{ ref: 'https://www.notion.so/acme/Staging-4f2a', document: 'Staging-4f2a.md', url: 'https://www.notion.so/acme/Staging-4f2a', source: 'Team wiki', stale: false }], createdAt: '2026-10-29T16:00:00Z' },
  { id: 'mem_5', kind: 'fact', statement: 'Releases go out on Tuesdays.', subject: 'releases', status: 'candidate', scope: 'personal', origin: 'agent', suggestedBy: 'codex-cli', tainted: false, duplicateOf: { id: 'mem_1', statement: 'Releases ship on Tuesdays, never on a Friday.' }, evidence: [], createdAt: '2026-10-30T10:00:00Z' },
  { id: 'mem_6', kind: 'fact', statement: 'Deploys are frozen during the last week of December.', subject: 'deploys', status: 'outdated', scope: 'personal', origin: 'extracted', tainted: false, evidence: [vaultEvidence('ops/freeze.md', 'Holidays', true)], createdAt: '2026-09-01T09:00:00Z' },
];

/** Every memory press answered from the scene: a confirmed rule waits on a signature, and a read says what it found. */
function memoryAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  const learn = { items: previewMemory.filter((item) => item.status === 'candidate' || item.status === 'conflicting'), more: 0 };
  const scoped = (item: MemoryItemView) => request.memoryScope === undefined || item.scope === request.memoryScope;
  switch (request.method) {
    case 'memory-learn':
    case 'memory-reject':
    case 'memory-edit':
      return { memoryLearn: learn };
    case 'memory-confirm': {
      const item = previewMemory.find((each) => each.id === request.memoryItemId);
      return { memoryLearn: learn, ...(item === undefined ? {} : { memoryItem: item }), ...(item !== undefined && item.kind === 'rule' ? { proposed: 'prp_preview' } : {}) };
    }
    case 'memory-facts':
      return { memoryFacts: { items: previewMemory.filter((item) => item.status === (request.memoryStatus ?? 'verified') && scoped(item)), more: 0 } };
    case 'memory-search': {
      const words = (request.memoryQuery ?? '').toLowerCase();
      return { memoryFacts: { items: previewMemory.filter((item) => item.statement.toLowerCase().includes(words) && scoped(item)), more: 0 } };
    }
    case 'memory-source-read':
      return {
        memorySources: previewMemorySources,
        memoryRead: { sourceId: request.memorySourceId ?? '', documents: 14, passages: 61, added: 3, merged: 2, rejectedBefore: 1, droppedCitations: 1, discarded: 0, outdated: 0, extractor: previewState === 'no-agent' ? 'unavailable' : 'answered' },
      };
    case 'memory-forget':
      return {};
    default:
      return { memorySources: previewMemorySources };
  }
}

/** The local network off, or on and listening with a phone over it: `?page=network&state=lan-on`. */
const previewLan: LanStatus =
  previewState === 'lan-on'
    ? { on: true, listening: true, addresses: ['192.168.1.20'], port: 47_820, advertised: true, instance: 'mx-7f3a', reachable: [{ deviceId: 'dev_1', name: 'Sam’s iPhone' }] }
    : { on: false, listening: false, addresses: [], advertised: false, reachable: [] };

const syncKinds = [
  { kind: 'servers', items: 3 },
  { kind: 'skills', items: 2 },
  { kind: 'projects', items: 2 },
  { kind: 'rules', items: 5 },
  { kind: 'memory', items: 7 },
];

/** Personal sync ready with a laptop waiting for the key, or the new machine's side: `state=key-arrived`, `state=not-on-plan`. */
function previewSync(): PersonalSyncStatus {
  const base = { kinds: syncKinds, conflicts: 0, skipped: [], openedElsewhere: [], waiting: [] };
  if (previewState === 'key-arrived') return { ...base, state: 'key-arrived', said: 'A sync key arrived from another of your machines. Compare the fingerprint and accept it to start syncing.', arrivedFingerprint: '40917 22618 73501 09344 51872 66230' };
  if (previewState === 'not-on-plan') return { ...base, state: 'not-on-plan', said: 'Your plan does not carry personal sync, so what is here stays on this machine.' };
  return {
    ...base,
    state: 'ready',
    said: 'Synced. Your other machines have everything this one carries.',
    keyId: 'Hc2f9Qm1vT0aXr7LdPe4Zw',
    lastSyncedAt: '2026-10-30T11:52:00Z',
    conflicts: 1,
    skipped: ['The skill design-review is larger than one item may be, so it stays on this machine.'],
    openedElsewhere: ['github.com/acme/billing'],
    waiting: [{ machineId: 'sam-laptop', fingerprint: '40917 22618 73501 09344 51872 66230', sealed: false }],
  };
}

const previewConflicts: PersonalSyncConflict[] = [
  { id: 'cfl_1', kind: 'skills', name: 'release-notes', writtenBy: 'sam-laptop', keptAt: '2026-10-30T10:15:00Z', theirs: 'Write the release notes from the merged pull requests, newest first.', mine: 'Write the release notes from the merged pull requests, grouped by area.' },
];

/** Every personal sync press answered from the scene: an offer or an accept waits on a signature. */
function syncAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  const personalSync = previewSync();
  if (request.method === 'personal-sync-conflicts') return { personalSync, syncConflicts: previewConflicts };
  if (request.method === 'personal-sync-key-offer' || request.method === 'personal-sync-key-accept') return { personalSync, proposed: 'prp_preview' };
  return { personalSync };
}

/** The community index: a skill already held at an older version, a pack, and a skill whose every version was marked unsafe. */
const previewIndex: CommunityIndexView = {
  source: 'https://memnox.com/index.json',
  marketplace: true,
  fetchedAt: '2026-10-30T11:40:00Z',
  complete: true,
  ...(previewState === 'offline' ? { said: 'The index could not be reached, so this is what was read this morning.' } : {}),
  entries: [
    { id: 'lst_review', name: 'review-checklist', kind: 'skill', description: 'Walks a pull request against the team checklist before it is sent for review', category: 'Code review', publisher: { kind: 'organization', name: 'Acme' }, license: 'MIT', agents: ['claude-code', 'codex-cli'], latest: { version: '2.1.0', digest: 'sha256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b' }, yanked: ['2.0.0'], unsafe: false, installed: '1.4.0', needs: { filesystem: ['./.github/pull_request_template.md'], network: [], commands: ['git diff', 'gh pr view'], mcpServers: ['github'], tools: ['Read', 'Bash'] }, warnings: [] },
    { id: 'lst_pushes', name: 'careful-pushes', kind: 'rule_pack', description: 'Asks before a push to main, a force push or a deleted branch', category: 'Git', publisher: { kind: 'member', name: 'Priya Shah' }, license: 'Apache-2.0', agents: [], latest: { version: '1.0.2', digest: 'sha256:1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c' }, yanked: [], unsafe: false, needs: { filesystem: [], network: [], commands: [], mcpServers: [], tools: [] }, warnings: [] },
    { id: 'lst_scrape', name: 'site-scraper', kind: 'skill', description: 'Fetches pages and keeps their text for later', category: 'Research', publisher: { kind: 'member', name: 'jdoe' }, agents: ['claude-code'], yanked: ['0.3.0', '0.3.1'], unsafe: true, needs: { filesystem: ['~/.cache/site-scraper'], network: ['*'], commands: ['curl'], mcpServers: [], tools: ['WebFetch'] }, warnings: ['It reaches any host on the internet, not only the sites you name.', 'It runs curl, which can send what it reads anywhere.'] },
    { id: 'lst_standup', name: 'standup-notes', kind: 'skill', description: 'Writes yesterday into three lines for the morning standup', category: 'Writing', publisher: { kind: 'member', name: 'Lee' }, agents: [], latest: { version: '0.4.0', digest: 'sha256:5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f' }, yanked: [], unsafe: false, warnings: ['Its publisher is a member rather than an organization, and nobody has reviewed it yet.'] },
  ],
};

/** Index answers from the scene: the words and kind filter as the runtime would, and an install says what waits. */
function indexAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  const words = (request.indexQuery ?? '').toLowerCase();
  const entries = previewIndex.entries.filter((entry) => (request.indexKind === undefined || entry.kind === request.indexKind) && `${entry.name} ${entry.description}`.toLowerCase().includes(words));
  const communityIndex = { ...previewIndex, entries };
  // Another index only waits on the island, so the scene keeps showing the marketplace, as the runtime does.
  if (request.method === 'index-source-set') return { communityIndex: previewIndex, ...(request.indexSource === undefined || request.indexSource === 'marketplace' ? {} : { proposed: 'prp_preview' }) };
  if (request.method !== 'index-install') return { communityIndex };
  const entry = previewIndex.entries.find((each) => each.name === request.indexName || each.id === request.indexName);
  if (entry === undefined || entry.latest === undefined) return { communityIndex };
  const pack = entry.kind === 'rule_pack';
  return { communityIndex: previewIndex, indexInstalled: { id: entry.id, name: entry.name, kind: entry.kind, version: request.indexVersion ?? entry.latest.version, digest: entry.latest.digest, proposed: pack ? ['prp_preview_1', 'prp_preview_2', 'prp_preview_3'] : [], held: !pack, said: '' } };
}

/** Two profiles: one whole, one naming a server the MCP Hub no longer holds. */
const previewProfiles: ProfileView[] = [
  { id: 'backend-engineering', name: 'Backend Engineering', description: 'Reviews, release notes and the local database, with careful pushes', skills: ['release-notes', 'review-checklist'], mcpServers: ['github', 'postgres'], rulePack: { name: 'Careful', rules: 6 }, updatedAt: '2026-10-28T09:00:00Z', missing: [] },
  { id: 'docs-writer', name: 'Docs writer', skills: ['release-notes'], mcpServers: ['figma'], updatedAt: '2026-10-21T09:00:00Z', missing: ['figma is no longer in the MCP Hub.'] },
];

function profileAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  if (request.method === 'profile-apply') return { profiles: previewProfiles, profileApplied: { profile: request.profileName ?? '', agent: request.profileAgent ?? '', proposed: ['prp_preview_1', 'prp_preview_2'], already: ['github'], skipped: [] } };
  return { profiles: previewProfiles };
}

/** Every method a page asks, answered from the scene. */
function answer(request: DaemonRequest): DaemonResponse[] {
  const ok = { id: request.id, ok: true };
  if (request.method.startsWith('memory-')) return [{ ...ok, ...memoryAnswer(request) }];
  if (request.method.startsWith('index-')) return [{ ...ok, ...indexAnswer(request) }];
  if (request.method === 'profiles' || request.method.startsWith('profile-')) return [{ ...ok, ...profileAnswer(request) }];
  if (request.method.startsWith('personal-sync-')) return [{ ...ok, ...syncAnswer(request) }];
  if (request.method === 'lan-status') return [{ ...ok, lan: previewLan }];
  if (request.method === 'lan-set') return [{ ...ok, lan: previewLan, ...(request.lanOn === true ? { proposed: 'prp_preview' } : {}) }];
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
  if (request.method === 'skills-hub' || request.method.startsWith('skill-')) return [{ ...ok, ...skillAnswer(request) }];
  if (request.method === 'projects' || request.method.startsWith('project-')) return [{ ...ok, ...projectAnswer(request) }];
  if (request.method === 'backup-create') return [{ ...ok, backupArchive: 'memnox-backup:v1:preview-sealed-archive', backupSummary: { ...previewBackup, ledger: request.backupLedger === true } }];
  if (request.method === 'backup-restore') return [{ ...ok, proposed: 'prp_preview', backupSummary: previewBackup }];
  if (request.method === 'rule-packs') return [{ ...ok, rulePacks: previewPacks }];
  if (request.method === 'rule-pack-import') return [{ ...ok, packProposed: ['prp_preview_1', 'prp_preview_2'] }];
  if (request.method === 'agent-launch') return [{ ...ok, agentLaunched: { agent: request.agentKind ?? '', workingDirectory: request.workingDirectory ?? '', line: request.agentKind === 'codex-cli' ? 'codex' : 'claude' }, ...(request.profileName === undefined ? {} : { proposed: 'prp_preview_1', ...profileAnswer({ ...request, method: 'profile-apply', profileAgent: request.agentKind }) }) }];
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

/** The hub after any skill press: a give, an accept or a widening rollback waits on a signature, the rest are done. */
function skillAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  const signed = (request.method === 'skill-assign' && request.skillOn === true) || request.method === 'skill-accept';
  if (request.method === 'skill-sync') return { skillsHub: previewSkills, skillsSynced: { written: 3, removed: 1, files: ['~/.claude/skills/release-notes/SKILL.md'], skipped: [] } };
  return { skillsHub: previewSkills, ...(signed ? { proposed: 'prp_preview' } : {}) };
}

/** The projects after any press: opening or applying writes instructions at once and proposes what widens. */
function projectAnswer(request: DaemonRequest): Partial<DaemonResponse> {
  const view = { projects: previewProjects };
  if (request.method === 'project-open' || request.method === 'project-apply') {
    return { projects: view, projectApplied: { written: ['CLAUDE.md', 'AGENTS.md'], removed: [], kept: [], governed: [], missing: ['figma'] }, proposed: 'prp_preview' };
  }
  return { projects: view };
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
