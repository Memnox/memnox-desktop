import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { isVoiceScene, previewVoice, VOICE_SCENES } from './voice/preview-voice';
import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { HeldCalls, ProposalCards, RequestIds, Setup, Signer, Talking, VoiceSettings, type ConfirmKey, type DaemonLink, type Runtime, type Speaker, type TalkState } from '../core';
import { AgentQuestions, HistoryKeeper, Sessions, type HistoryStore } from '../core';
import { Island, type IslandParts, type IslandPreview, type WorkingSession } from './Island';
import { Board } from './sessions/Board';
import { LiveSession } from './sessions/LiveSession';
import { PREVIEW_CARDS, PREVIEW_VIEWS, previewQuestion } from './sessions/preview-data';
import { AgentMark, ToolMark } from './kit';
import { SidePanel } from './sessions/SidePanel';
import { Switcher } from './sessions/Switcher';
import './styles.css';

/**
 * The island as a designer sees it, in a browser with no Tauri and no daemon: `pnpm dev`, then open
 * /preview.html?mode=held, or any scene below, over a scripted daemon. /preview.html alone lists them.
 */
const SCENES = [
  'peek',
  'peek-hover',
  'compact',
  'compact-hover',
  'empty',
  'empty-countdown',
  'voice',
  'hearing',
  'held',
  'held-queue',
  'held-local',
  'held-settled',
  'held-menu',
  'finished',
  'rule',
  'draft',
  'settings',
  'setup',
  /** Rests as a peek, then a call arrives after a second, to watch the island grow. */
  'grow',
  'sessions-compact',
  'sessions-overview',
  'sessions-detail',
  'sessions-question',
  'sessions-question-multi',
  'sessions-launcher',
  'sessions-launcher-tools',
  'sessions-launcher-tool',
  /** The session windows, each shot at its own size. */
  'sessions-live',
  'sessions-live-changes',
  'sessions-side',
  'sessions-switcher',
  'sessions-board',
  /** The person's own turn: the question over its answer arriving, a long one opened tall, and one picked from the history. */
  'conversation',
  'answer-long',
  'answer-picked',
  ...VOICE_SCENES,
] as const;
type Scene = (typeof SCENES)[number];

const asked = new URLSearchParams(window.location.search);
// The old `?settings` still opens on the settings.
const scene: Scene | undefined = asked.has('settings') ? 'settings' : (SCENES as readonly string[]).includes(asked.get('mode') ?? '') ? (asked.get('mode') as Scene) : undefined;

const at = new Date().toISOString();

const held: DaemonEvent = {
  kind: 'held',
  subject: 'hld_preview',
  agent: 'agt_codex',
  agentName: 'Codex',
  summary: 'Codex wants to push to main',
  what: 'git push --force-with-lease origin feature/island-restyle-for-windows-and-linux:main',
  why: 'wants to push to main',
  place: 'memnox-web',
  at,
};

const older: DaemonEvent = {
  ...held,
  subject: 'hld_older',
  agent: 'agt_claude-code',
  agentName: 'Claude Code',
  what: 'rm -rf ./dist && pnpm build',
  why: undefined,
};

const finished: DaemonEvent = {
  kind: 'notice',
  subject: 'ses_preview',
  agent: 'agt_claude-code',
  agentName: 'Claude Code',
  summary: 'Moved the island onto the kit, fixed the held call card and every test passes.',
  notice: 'finished',
  sessionId: 'ses_preview',
  at,
};

/** What waits when the island opens, and what the live feed says after. */
function script(): { waiting: DaemonEvent[]; feed: DaemonEvent[] } {
  switch (scene) {
    case 'held':
    case 'held-menu':
      return { waiting: [held], feed: [] };
    case 'held-queue':
      return { waiting: [older, held], feed: [] };
    case 'held-local':
      return { waiting: [{ ...held, withinSession: true, what: 'pnpm test', why: 'runs inside its repository' }], feed: [] };
    case 'held-settled':
      return { waiting: [held], feed: [{ ...held, kind: 'settled' }] };
    case 'grow':
      return { waiting: [], feed: [held] };
    default:
      return { waiting: [], feed: [] };
  }
}

const { waiting, feed } = script();
const link: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    if (request.method === 'waiting') yield { id: request.id, ok: true, waiting };
    else if (request.method === 'sessions-list') yield { id: request.id, ok: true, sessions: scene?.startsWith('sessions-') === true ? PREVIEW_CARDS : [] };
    else if (request.method === 'session-view')
      yield {
        id: request.id,
        ok: true,
        session: PREVIEW_VIEWS[request.sessionId ?? ''],
        diff: request.path === undefined ? undefined : { path: request.path, lines: ['@@ -40,6 +40,9 @@ export function Island', '   const held = useSyncExternalStore(', '-  const working = [];', '+  const working = sessions.working;', '+  const focus = sessions.focusCard;', '+  const questions = useQuestions();', '   return ('] },
      };
    else if (request.method === 'voice-agents')
      yield {
        id: request.id,
        ok: true,
        voiceAgents: [
          { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, works: true, chosen: true, install: '' },
          { kind: 'codex', label: 'Codex', installed: true, sealed: true, works: false, because: 'It did not call a Memnox tool when asked.', chosen: false, install: '' },
          { kind: 'cursor', label: 'Cursor', installed: false, sealed: true, chosen: false, install: 'Install the Cursor CLI: curl https://cursor.com/install -fsS | bash' },
        ],
      };
    else if (request.method === 'subscribe') {
      yield { id: request.id, ok: true };
      if (scene === 'grow') await new Promise((resolve) => setTimeout(resolve, 1000));
      for (const event of feed) yield { id: request.id, ok: true, event };
      await new Promise(() => undefined);
    } else yield { id: request.id, ok: true };
  },
};
const key: ConfirmKey = { publicPoint: async () => undefined, sign: async () => undefined };
const speaker: Speaker = { queue: () => undefined, drained: async () => undefined, stop: () => undefined };

const ids = new RequestIds();
const signer = new Signer(link, key, ids);
// A timer that never fires, so a settled card stays on screen to be looked at.
const calls = new HeldCalls(link, signer, ids, { timer: () => () => undefined });
const cards = new ProposalCards(link, signer, speaker, ids);
const talking = new Talking(link, speaker, signer, ids, { timer: () => () => undefined, cards });
const runtime: Runtime = { found: async () => true, install: async () => true, wired: async () => true, run: async () => true };
// The setup scene cannot find the runtime, so its pill hangs under the island.
const setup = new Setup(link, scene === 'setup' ? { ...runtime, found: async () => false, install: async () => false } : runtime, ids, async () => undefined);
if (scene === 'setup') void setup.ensure();
const voiceSettings = new VoiceSettings(link, ids);
void calls.watch();
// The sessions read once, the timer never firing, so each screen holds still to be looked at.
const sessionList = new Sessions(link, ids, () => () => undefined);
const questions = new AgentQuestions(link, ids, () => () => undefined);
if (scene === 'sessions-question' || scene === 'sessions-question-multi') questions.handle(previewQuestion(scene === 'sessions-question-multi'));
if (scene === 'sessions-question-multi') questions.toggle('Side panel');
if (scene === 'sessions-overview' || scene === 'sessions-detail') sessionList.opened(true);
if (scene === 'sessions-detail') sessionList.showDetail(true);
void sessionList.refresh();
const kept: string = JSON.stringify({
  exchanges: [
    { id: 'e1', question: 'What is Claude Code doing right now?', answer: 'It is porting the session screens.', askedAt: Date.now() - 4 * 60_000, answeredAt: Date.now() - 4 * 60_000 + 2_400 },
    { id: 'e2', question: 'Push the fix to main', answer: '', askedAt: Date.now() - 30 * 60_000, answeredAt: Date.now() - 30 * 60_000 + 9_000, failure: 'Memnox did not answer' },
    { id: 'e3', question: 'Which sessions finished yesterday?', answer: 'Two: Codex and Cursor.', askedAt: Date.now() - 26 * 3_600_000, answeredAt: Date.now() - 26 * 3_600_000 + 3_100 },
  ],
});
const previewStore: HistoryStore = { load: () => kept, save: () => undefined };

if (scene === 'rule')
  cards.show({
    ...held,
    kind: 'proposal',
    subject: 'prp_rule',
    rule: {
      summary: 'deny git push to main',
      effect: 'deny',
      action: 'git.push',
      branches: ['main', 'release/*'],
      reason: 'You asked for every push to main to stop here.',
      scopes: [
        { id: 'machine', kind: 'machine', label: 'This computer' },
        { id: 'repo', kind: 'repository', label: 'memnox-web', folder: '~/code/memnox-web', suggested: true },
        { id: 'team', kind: 'team', label: 'The team' },
      ],
    },
  });

if (scene === 'draft')
  cards.show({
    ...held,
    kind: 'proposal',
    subject: 'prp_work',
    work: {
      toolkit: 'slack',
      tool: 'SLACK_SEND_MESSAGE',
      kind: 'message',
      account: { name: 'Ana Moreau', check: 'matched' },
      to: ['#releases', '#desktop'],
      body: 'The Windows and Linux island now matches the Mac: same buttons, colours, shapes and motion. Shots are in the thread.',
      fields: [
        { name: 'unfurl_links', value: 'false' },
        { name: 'thread_ts', value: '1760788800.000100' },
      ],
    },
  });

const talk = (state: Partial<TalkState>): TalkState => ({ phase: 'listening', heard: undefined, reply: '', failure: undefined, ...state });
const sessions: WorkingSession[] = [
  { sessionId: 'ses_1', agent: 'agt_claude-code' },
  { sessionId: 'ses_2', agent: 'agt_codex' },
  { sessionId: 'ses_3', agent: 'agt_gemini' },
];

function previewOf(shown: Scene | undefined): { preview: IslandPreview; working?: readonly WorkingSession[] } {
  switch (shown) {
    case 'peek-hover':
      return { preview: { hovering: true } };
    case 'compact':
      return { preview: {}, working: sessions };
    case 'compact-hover':
      return { preview: { hovering: true }, working: sessions };
    case 'empty':
      return { preview: { opened: true } };
    case 'empty-countdown':
      return { preview: { opened: true, countdown: 0.6 } };
    case 'voice':
      return { preview: { talk: talk({}) } };
    case 'hearing':
      return { preview: { talk: talk({ heard: 'push the fix to main and tell the team on Slack' }) } };
    case 'finished':
      return { preview: { finished: { agent: finished.agent, who: finished.agentName ?? '', summary: finished.summary, sessionId: finished.sessionId } } };
    case 'settings':
      return { preview: { settings: true, opened: true } };
    case 'sessions-compact':
      return { preview: {} };
    case 'sessions-overview':
      return { preview: { opened: true } };
    case 'sessions-detail':
      return { preview: { opened: true, detail: true } };
    case 'sessions-launcher':
      return { preview: { opened: true, launcher: 'actions' } };
    case 'sessions-launcher-tools':
      return { preview: { opened: true, launcher: 'tools' } };
    case 'conversation':
      return { preview: { talk: talk({ phase: 'speaking', heard: 'what changed in the island since this morning', reply: PREVIEW_REPLY.slice(0, 210) }) } };
    case 'answer-long':
      return { preview: { talk: talk({ phase: 'listening', heard: 'what changed in the island since this morning', reply: PREVIEW_REPLY }) } };
    case 'answer-picked':
      return { preview: { opened: true, picked: { id: 'x_1', question: 'why did the build fail on Windows', answer: PREVIEW_REPLY, askedAt: Date.now() - 600_000, answeredAt: Date.now() - 588_000 } } };
    case 'sessions-launcher-tool':
      return { preview: { opened: true, launcher: 'tool', tool: { toolkit: 'github', connected: true } } };
    default:
      return { preview: {} };
  }
}

/** A reply long enough to open tall, in the markdown the brain writes. */
const PREVIEW_REPLY = [
  'Three things changed in the island this morning:',
  '',
  '1. **Answers show again.** Your question sits in a bubble with the reply arriving under it.',
  '2. **Long replies open tall**, and one picked from the history opens the same way.',
  '3. **Clicks pass through** everywhere outside the shape, on Windows and on Linux.',
  '',
  'The card wall lets clicks through between its cards too, so the editor under it keeps working. Nothing else moved, and the tests pass on all three systems.',
].join('\n');

/** The list of scenes, for /preview.html with none chosen. */
function Index() {
  return (
    <ul style={{ position: 'fixed', bottom: 12, left: 12, margin: 0, padding: 12, background: '#111', color: '#fff', font: '12px system-ui', listStyle: 'none', columns: 3, borderRadius: 8 }}>
      {SCENES.map((each) => (
        <li key={each}>
          <a style={{ color: '#8cc8ff' }} href={`?mode=${each}`}>
            {each}
          </a>
        </li>
      ))}
    </ul>
  );
}

const { preview, working } = scene === 'voice-speaking' ? { preview: { talk: talk({ phase: 'speaking', reply: 'Two sessions are working.' }) }, working: undefined } : previewOf(scene);
const parts: IslandParts = {
  calls,
  talking,
  cards,
  setup,
  voiceSettings,
  preview,
  working,
  onOpenSession: () => undefined,
  voice: isVoiceScene(scene) ? previewVoice(scene, talking, speaker) : undefined,
  sessions: sessionList,
  questions,
  launcher: {
    actions: { sayRule: () => undefined, whatHappened: () => undefined, phones: () => undefined, dictation: () => undefined, settings: () => undefined },
    facts: { toolsCaption: '2 connected' },
    tools: scene === 'sessions-launcher-tools' ? previewTools() : undefined,
    toolsNote: undefined,
  },
};

/** The Tools page as the launcher reads it: the agents, then the connected apps. */
function previewTools() {
  return [
  { id: 'agent:claude-code', title: 'Claude Code', caption: 'Voice', mark: <AgentMark agent="claude-code" name="Claude Code" size={25} /> },
  { id: 'agent:codex', title: 'Codex', caption: 'Ready', mark: <AgentMark agent="codex" name="Codex" size={25} /> },
  { id: 'app:github', title: 'GitHub', caption: 'Connected', mark: <ToolMark toolkit="github" size={25} online={false} />, onPress: () => undefined },
  { id: 'app:slack', title: 'Slack', caption: 'Connected', mark: <ToolMark toolkit="slack" size={25} online={false} />, onPress: () => undefined },
  { id: 'app:linear', title: 'Linear', caption: 'Sign in again', mark: <ToolMark toolkit="linear" size={25} online={false} />, onPress: () => undefined },
];
}

/** The session windows, drawn alone at their own size as their pages draw them. */
function SessionWindow({ shown }: { shown: Scene }) {
  switch (shown) {
    case 'sessions-live':
    case 'sessions-live-changes':
      return (
        <div data-theme="dark" style={{ width: 620, height: 820 }}>
          <LiveSession sessionId="ses_claude" sessions={sessionList} calls={calls} onClose={() => undefined} onOpenFolder={() => undefined} initial={PREVIEW_VIEWS.ses_claude} />
        </div>
      );
    case 'sessions-side':
      return (
        <div data-theme="dark" style={{ width: 330, height: 700 }}>
          <SidePanel calls={calls} sessions={sessionList} history={new HistoryKeeper(previewStore, () => 'id')} pinned={false} onPin={() => undefined} onOpenSession={() => undefined} onAskAgain={() => undefined} />
        </div>
      );
    case 'sessions-switcher':
      return (
        <div data-theme="dark" style={{ width: 1280, height: 800, background: 'linear-gradient(135deg, #1d2a3a, #3a2a1d)' }}>
          <Switcher cards={PREVIEW_CARDS} target="ses_codex" onDone={() => undefined} still />
        </div>
      );
    case 'sessions-board':
      return (
        <div data-theme="dark" style={{ width: 976, height: 1100, background: 'linear-gradient(135deg, #1d2a3a, #3a2a1d)' }}>
          <Board sessions={sessionList} title="Your sessions" onWatch={() => undefined} onClose={() => undefined} initial={[PREVIEW_VIEWS.ses_claude!, PREVIEW_VIEWS.ses_codex!, PREVIEW_VIEWS.ses_cursor!]} />
        </div>
      );
    default:
      return null;
  }
}
const windowScene = scene !== undefined && ['sessions-live', 'sessions-live-changes', 'sessions-side', 'sessions-switcher', 'sessions-board'].includes(scene);
// The changes scene opens its tab and a file once the window is drawn, so the diff can be looked at.
if (scene === 'sessions-live-changes')
  setTimeout(() => {
    (document.querySelector('[aria-pressed][class*="flex-1"]:nth-child(3)') as HTMLButtonElement | null)?.click();
    setTimeout(() => (document.querySelector('[title$="Island.tsx"]') as HTMLButtonElement | null)?.click(), 300);
  }, 900);

// The held menu scene opens the ellipsis once the card is drawn, so the menu can be looked at.
if (scene === 'held-menu') setTimeout(() => (document.querySelector('[aria-label="More answers"]') as HTMLButtonElement | null)?.click(), 900);

const root = document.getElementById('root');
if (root === null) throw new Error('preview.html has no root');
createRoot(root).render(
  <StrictMode>
    {windowScene && scene !== undefined ? <SessionWindow shown={scene} /> : <Island {...parts} />}
    {scene === undefined && <Index />}
  </StrictMode>,
);
