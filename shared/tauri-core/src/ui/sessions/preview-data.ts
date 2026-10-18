import type { DaemonEvent, SessionCard, SessionView } from '@memnox/core/wire';

/**
 * The sessions the preview shows with no daemon behind it: three agents at work on this computer, each
 * read up close, and an agent's question with two parts, so every session screen can be looked at.
 */

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

export const PREVIEW_CARDS: SessionCard[] = [
  {
    sessionId: 'ses_claude',
    agent: 'claude-code',
    agentName: 'Claude Code',
    task: 'Port the island session screens to the Windows and Linux app',
    state: 'working',
    thinking: true,
    repository: 'memnox-desktop',
    runningIn: 'Windows Terminal',
    lastActive: minutesAgo(0),
    host: { cwd: '/home/ana/code/memnox-desktop' },
  },
  {
    sessionId: 'ses_codex',
    agent: 'codex',
    agentName: 'Codex',
    task: 'Fix the flaky sign in test',
    state: 'working',
    thinking: false,
    repository: 'memnox-cloud',
    runningIn: 'VS Code',
    lastActive: minutesAgo(1),
  },
  {
    sessionId: 'ses_cursor',
    agent: 'cursor',
    agentName: 'Cursor',
    task: 'Tidy the pricing page copy',
    state: 'open',
    thinking: false,
    repository: 'memnox-web',
    runningIn: 'Cursor',
    lastActive: minutesAgo(12),
  },
  {
    sessionId: 'ses_gemini',
    agent: 'gemini',
    agentName: 'Gemini',
    state: 'quiet',
    thinking: false,
    repository: 'memnox-runtime',
    runningIn: 'GNOME Terminal',
    lastActive: minutesAgo(95),
  },
];

const VIEW: SessionView = {
  sessionId: 'ses_claude',
  agent: 'claude-code',
  agentName: 'Claude Code',
  task: 'Port the island session screens to the Windows and Linux app',
  lastAsk: 'and shoot every scene before you commit',
  state: 'working',
  thinking: true,
  repository: 'memnox-desktop',
  branch: 'main',
  runningIn: 'Windows Terminal',
  where: 'a Windows Terminal tab',
  startedAt: minutesAgo(42),
  lastActive: minutesAgo(0),
  waitingOnYou: 0,
  helpers: ['Reading the Mac overview for its spacing'],
  steps: [
    { at: minutesAgo(9), surface: 'filesystem', text: 'Read /home/ana/code/memnox-desktop/macos/Sources/MemnoxVoice/Presentation/Island/IslandOverview.swift' },
    { at: minutesAgo(6), surface: 'shell', text: 'pnpm test' },
    { at: minutesAgo(4), surface: 'network', text: 'GET https://registry.npmjs.org/lucide-react' },
    { at: minutesAgo(3), surface: 'filesystem', text: 'Edit /home/ana/code/memnox-desktop/shared/tauri-core/src/ui/sessions/IslandSessions.tsx' },
    { at: minutesAgo(1), surface: 'shell', text: 'cargo clippy --workspace --all-targets', refused: true },
    { at: minutesAgo(0), surface: 'filesystem', text: 'Edit /home/ana/code/memnox-desktop/shared/tauri-core/src/ui/Island.tsx' },
  ],
  files: [
    { path: 'shared/tauri-core/src/ui/sessions/IslandSessions.tsx', added: 312, removed: 0 },
    { path: 'shared/tauri-core/src/ui/Island.tsx', added: 96, removed: 14 },
    { path: 'shared/tauri-core/src/core/application/sessions.ts', added: 148, removed: 0 },
    { path: 'shared/tauri-core/src/core/domain/session-text.ts', added: 260 },
    { path: 'shared/tauri-core/test/sessions.test.ts', added: 301, removed: 2 },
    { path: 'shared/tauri-core/src-tauri/src/sessions.rs', added: 220, removed: 0 },
    { path: 'shared/tauri-core/sessions.html', added: 12 },
  ],
  conversation: [
    { at: minutesAgo(42), who: 'person', text: 'Port the island session screens to the Windows and Linux app' },
    { at: minutesAgo(40), who: 'agent', text: 'I will start from the Mac overview and the spec, then wire the daemon session list into the island.' },
    { at: minutesAgo(30), who: 'tool', text: 'Read IslandOverview.swift' },
    { at: minutesAgo(8), who: 'person', text: 'and shoot every scene before you commit' },
    { at: minutesAgo(7), who: 'agent', text: 'Will do. The overview, the detail and the question are drawn; the launcher is next.' },
  ],
  lastSaid: 'The overview, the detail and the question are drawn; the launcher is next.',
};

export const PREVIEW_VIEWS: Record<string, SessionView> = {
  ses_claude: VIEW,
  ses_codex: {
    ...VIEW,
    sessionId: 'ses_codex',
    agent: 'codex',
    agentName: 'Codex',
    task: 'Fix the flaky sign in test',
    lastAsk: undefined,
    thinking: false,
    repository: 'memnox-cloud',
    branch: 'fix/sign-in',
    runningIn: 'VS Code',
    waitingOnYou: 1,
    helpers: [],
    steps: VIEW.steps.slice(0, 3),
    files: VIEW.files.slice(4, 5),
    conversation: undefined,
    lastSaid: undefined,
  },
  ses_cursor: { ...VIEW, sessionId: 'ses_cursor', agent: 'cursor', agentName: 'Cursor', state: 'open', thinking: false, task: 'Tidy the pricing page copy', lastAsk: undefined, steps: [], files: [], helpers: [], conversation: [] },
  ses_gemini: { ...VIEW, sessionId: 'ses_gemini', agent: 'gemini', agentName: 'Gemini', state: 'quiet', thinking: false, task: undefined, lastAsk: undefined, lastActive: minutesAgo(95), steps: [], files: [], helpers: [], conversation: [] },
};

export function previewQuestion(multi: boolean): DaemonEvent {
  return {
    kind: 'notice',
    notice: 'question',
    subject: 'q_preview',
    agent: 'claude-code',
    agentName: 'Claude Code',
    summary: 'Claude Code is asking which store to use',
    at: new Date().toISOString(),
    sessionId: 'ses_claude',
    questions: [
      {
        question: 'Where should the side panel keep its history between launches?',
        header: 'Storage',
        multiSelect: false,
        options: [
          { label: 'In the webview storage', description: 'Shared by every window of the app, nothing to install.' },
          { label: 'In a file beside the settings', description: 'Read by Rust, so it survives a cleared webview.' },
          { label: 'Not at all', description: 'Forget everything when the app quits.' },
        ],
      },
      {
        question: 'Which windows should open from the island?',
        header: 'Windows',
        multiSelect: true,
        options: [{ label: 'Live session' }, { label: 'Side panel' }, { label: 'Switcher' }, { label: 'Card wall' }],
      },
    ],
    answers: multi ? { 'Where should the side panel keep its history between launches?': 'In the webview storage' } : {},
  };
}
