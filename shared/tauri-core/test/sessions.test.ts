import type { DaemonEvent, SessionCard, SessionView, SessionViewStep } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { AgentQuestions } from '../src/core/application/agent-questions';
import { Displays, type Presenter } from '../src/core/application/displays';
import { HistoryKeeper, type HistoryStore } from '../src/core/application/history-keeper';
import { RequestIds } from '../src/core/application/request-ids';
import { Sessions } from '../src/core/application/sessions';
import type { TalkState } from '../src/core/application/talking';
import { ask, end, exchangeDetail, historyDays, NO_HISTORY, parseHistory, replied } from '../src/core/domain/history';
import { reactionTo } from '../src/core/domain/reaction';
import { isActive, sessionStatus, statusLabel } from '../src/core/domain/session-status';
import {
  ago,
  badgeLabel,
  cardSubtitle,
  cardTitle,
  currentAsk,
  detailPlace,
  diffLines,
  excerptLines,
  folderOf,
  meaningful,
  onlyNetwork,
  readable,
  repositoryName,
  shortPath,
  stepLine,
  stepSymbol,
  viewContext,
  viewPlace,
} from '../src/core/domain/session-text';
import { HandTimer, ScriptedDaemon } from './doubles';

const NOW = Date.parse('2026-10-18T12:00:00.000Z');
const minutesAgo = (minutes: number) => new Date(NOW - minutes * 60_000).toISOString();

const card = (sessionId: string, extra: Partial<SessionCard> = {}): SessionCard => ({
  sessionId,
  agent: 'claude-code',
  agentName: 'Claude Code',
  state: 'working',
  thinking: false,
  ...extra,
});

const view = (extra: Partial<SessionView> = {}): SessionView => ({
  sessionId: 'ses_1',
  agent: 'claude-code',
  agentName: 'Claude Code',
  state: 'working',
  thinking: false,
  waitingOnYou: 0,
  helpers: [],
  steps: [],
  files: [],
  ...extra,
});

const step = (surface: string, text: string, extra: Partial<SessionViewStep> = {}): SessionViewStep => ({ at: minutesAgo(1), surface, text, ...extra });

describe('a session at a glance', () => {
  it('lets a pause, then a call waiting, outrank anything the session is doing', () => {
    expect(sessionStatus({ state: 'working', thinking: true, paused: 'too many failures' })).toBe('paused');
    expect(sessionStatus({ state: 'working', thinking: true, waitingOnYou: 1 })).toBe('needs-you');
    expect(sessionStatus({ state: 'idle', thinking: true })).toBe('thinking');
    expect(sessionStatus({ state: 'open', thinking: false })).toBe('waiting-on-you');
    expect(sessionStatus({ state: 'whatever', thinking: false })).toBe('quiet');
  });

  it('counts only working and thinking as busy, and words each status as the badge does', () => {
    expect(isActive('working')).toBe(true);
    expect(isActive('waiting-on-you')).toBe(false);
    expect(statusLabel('waiting-on-you')).toBe('Waiting on you');
  });
});

describe('how a session reads', () => {
  it('drops terminal icon glyphs and control characters from what it was asked', () => {
    expect(readable('  fix\tthe   login\n')).toBe('fix the login');
    expect(readable('')).toBeUndefined();
    expect(repositoryName('./')).toBeUndefined();
  });

  it('says how long ago the way a person does, and a moment ahead is just now', () => {
    expect(ago(minutesAgo(0.5), NOW)).toBe('just now');
    expect(ago(minutesAgo(-1), NOW)).toBe('just now');
    expect(ago(minutesAgo(7), NOW)).toBe('7 min ago');
    expect(ago(minutesAgo(180), NOW)).toBe('3 h ago');
    expect(ago('not a date', NOW)).toBeUndefined();
  });

  it('titles a card by its task, then its repository, then its agent', () => {
    expect(cardTitle(card('a', { task: 'Fix the login' }))).toBe('Fix the login');
    expect(cardTitle(card('a', { repository: 'memnox-web' }))).toBe('memnox-web');
    expect(cardTitle(card('a'))).toBe('Claude Code');
  });

  it('subtitles a card with the agent, the repository and working or how long ago', () => {
    expect(cardSubtitle(card('a', { task: 'Fix it', repository: 'web', thinking: true }), NOW)).toBe('Claude Code · web · working');
    expect(cardSubtitle(card('a', { state: 'open', lastActive: minutesAgo(5) }), NOW)).toBe('5 min ago');
  });

  it('cuts paths to their last part and names a host by its site', () => {
    expect(stepLine(step('filesystem', 'Edit /Users/ana/code/web/src/app.ts'))).toBe('Edit app.ts');
    expect(stepLine(step('network', 'GET https://api.github.com/repos/x'))).toBe('Reached github.com');
  });

  it('keeps one line per thing done and leaves the network out unless it is all there is', () => {
    const steps = [step('shell', 'pnpm test'), step('network', 'GET https://a.com'), step('filesystem', 'Edit /a/b.ts'), step('shell', 'pnpm test')];
    expect(meaningful(steps).map((each) => each.text)).toEqual(['Edit /a/b.ts', 'pnpm test']);
    expect(meaningful([step('network', 'GET https://a.com')])).toHaveLength(1);
    expect(onlyNetwork([step('network', 'GET https://a.com')])).toBe(true);
  });

  it('draws a refusal, a failure, a read and a write each with its own symbol', () => {
    expect(stepSymbol(step('shell', 'rm', { refused: true }))).toBe('hand.raised');
    expect(stepSymbol(step('shell', 'rm', { failed: true }))).toBe('xmark.circle');
    expect(stepSymbol(step('filesystem', 'Read a.ts'))).toBe('doc.text');
    expect(stepSymbol(step('filesystem', 'Edit a.ts'))).toBe('pencil');
    expect(stepSymbol(step('config', 'x'))).toBe('circle');
  });

  it('places a view by repository and branch, and says where it runs and since when', () => {
    const session = view({ repository: 'web', branch: 'main', runningIn: 'Windows Terminal', startedAt: minutesAgo(30), lastActive: minutesAgo(2), state: 'open' });
    expect(viewPlace(session)).toBe('web on main');
    expect(detailPlace(session)).toBe('web · Windows Terminal');
    expect(viewContext(session, NOW)).toBe('Windows Terminal · started 30 min ago · active 2 min ago');
    expect(badgeLabel(view({ state: 'quiet', lastActive: minutesAgo(9) }), NOW)).toBe('Quiet, 9 min ago');
  });

  it('shows the follow up when the person asked something after the task', () => {
    expect(currentAsk({ task: 'Fix it', lastAsk: 'and add a test' })).toEqual({ words: 'and add a test', followUp: true });
    expect(currentAsk({ task: 'Fix it', lastAsk: 'Fix it' })).toEqual({ words: 'Fix it', followUp: false });
  });

  it('names a file by its last parts and its folder by the three above it', () => {
    expect(shortPath('/a/b/c/d.ts')).toBe('c/d.ts');
    expect(folderOf('a/b/c/d/e.ts')).toBe('b/c/d');
  });

  it('takes the shared indent off an excerpt and numbers a diff by side', () => {
    expect(excerptLines(['+    a', '-    b', '      c'])).toEqual([
      { added: true, text: 'a' },
      { added: false, text: 'b' },
      { added: true, text: '  c' },
    ]);
    expect(diffLines(['diff --git', '@@ -3,2 +3,3 @@ fn main', ' keep', '-old', '+new', '+more'])).toEqual([
      { kind: 'hunk', text: 'fn main' },
      { kind: 'context', text: 'keep', old: 3, new: 3 },
      { kind: 'removed', text: 'old', old: 4 },
      { kind: 'added', text: 'new', new: 4 },
      { kind: 'added', text: 'more', new: 5 },
    ]);
  });
});

describe('the sessions the island reads', () => {
  const daemon = (cards: SessionCard[], session?: SessionView) =>
    new ScriptedDaemon({
      'sessions-list': (request) => [{ id: request.id, ok: true, sessions: cards }],
      'session-view': (request) => [{ id: request.id, ok: true, session: session === undefined ? undefined : { ...session, sessionId: request.sessionId ?? '' } }],
    });

  it('leaves Memnox own operator out and counts only the busy ones as working', async () => {
    const sessions = new Sessions(daemon([card('a'), card('b', { agent: 'memnox-operator' }), card('c', { state: 'idle' })]), new RequestIds(), new HandTimer().start);
    await sessions.refresh();
    expect(sessions.state.cards.map((each) => each.sessionId)).toEqual(['a', 'c']);
    expect(sessions.working.map((each) => each.sessionId)).toEqual(['a']);
    expect(sessions.state.focusId).toBe('a');
  });

  it('reads the focused session up close only while the island is open', async () => {
    const link = daemon([card('a'), card('b')], view());
    const sessions = new Sessions(link, new RequestIds(), new HandTimer().start);
    await sessions.refresh();
    expect(link.sent('session-view')).toHaveLength(0);
    sessions.opened(true);
    sessions.focus('b');
    await sessions.refresh();
    expect(sessions.state.focused?.sessionId).toBe('b');
    expect(link.sent('session-view').at(-1)?.sessionId).toBe('b');
  });

  it('reads again on its timer, quickly while open', async () => {
    const timer = new HandTimer();
    const waits: number[] = [];
    const sessions = new Sessions(daemon([card('a')]), new RequestIds(), (ms, fire) => (waits.push(ms), timer.start(ms, fire)));
    sessions.start();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(waits.at(-1)).toBe(5_000);
    sessions.opened(true);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(waits.at(-1)).toBe(2_000);
    sessions.stop();
  });

  it('turns back to every session when the island closes', async () => {
    const sessions = new Sessions(daemon([card('a')]), new RequestIds(), new HandTimer().start);
    sessions.opened(true);
    sessions.showDetail(true);
    sessions.opened(false);
    expect(sessions.state.detail).toBe(false);
  });

  it('asks for one file diff by its path', async () => {
    const link = new ScriptedDaemon({ 'session-view': (request) => [{ id: request.id, ok: true, diff: { path: request.path ?? '', lines: ['@@ -1 +1 @@', '+a'] } }] });
    const diff = await new Sessions(link, new RequestIds(), new HandTimer().start).diff('a', 'src/a.ts');
    expect(diff?.path).toBe('src/a.ts');
  });
});

const question = (extra: Partial<DaemonEvent> = {}): DaemonEvent => ({
  kind: 'notice',
  notice: 'question',
  subject: 'q_1',
  agent: 'claude-code',
  agentName: 'Claude Code',
  summary: 'Claude Code asks which database',
  at: minutesAgo(0),
  questions: [
    { question: 'Which database?', options: [{ label: 'Postgres' }, { label: 'SQLite' }], multiSelect: false },
    { question: 'Which parts?', options: [{ label: 'API' }, { label: 'Web' }, { label: 'CLI' }], multiSelect: true },
  ],
  ...extra,
});

describe('an agent question answered with taps', () => {
  it('sends a pick as a confirm naming the question by number, then moves to the next', async () => {
    const link = new ScriptedDaemon({ confirm: (request) => [{ id: request.id, ok: true, outcome: 'answered' }] });
    const stopped: string[] = [];
    const questions = new AgentQuestions(link, new RequestIds(), new HandTimer().start, (subject) => stopped.push(subject));
    questions.handle(question());
    expect((await questions.pick('SQLite')).kind).toBe('answered');
    expect(link.sent('confirm')[0]).toMatchObject({ subject: 'q_1', answer: 'SQLite', questionNumber: 1 });
    expect(stopped).toEqual(['q_1']);
    questions.toggle('CLI');
    questions.toggle('API');
    await questions.done();
    expect(link.sent('confirm')[1]).toMatchObject({ answer: 'API, CLI', questionNumber: 2 });
    expect(questions.state.card).toBeUndefined();
  });

  it('skips what the daemon says is already picked, and goes when settled elsewhere', () => {
    const questions = new AgentQuestions(new ScriptedDaemon(), new RequestIds(), new HandTimer().start);
    questions.handle(question({ answers: { 'Which database?': 'Postgres' } }));
    expect(questions.state.card?.answers['Which database?']).toBe('Postgres');
    questions.handle({ ...question(), kind: 'settled', notice: undefined });
    expect(questions.state.card).toBeUndefined();
  });

  it('keeps the card with a reason when the pick did not go through, and clears the reason later', async () => {
    const timer = new HandTimer();
    const link = new ScriptedDaemon({ confirm: (request) => [{ id: request.id, ok: false, error: 'the agent stopped waiting' }] });
    const questions = new AgentQuestions(link, new RequestIds(), timer.start);
    questions.handle(question());
    expect((await questions.pick('Postgres')).kind).toBe('failed');
    expect(questions.state.error).toBe('the agent stopped waiting');
    timer.fireAll();
    expect(questions.state.error).toBeUndefined();
    expect(questions.state.card).toBeDefined();
  });
});

class RecordingPresenter implements Presenter {
  readonly calls: string[] = [];
  opens = true;
  live = async (sessionId: string) => void this.calls.push(`live ${sessionId}`);
  turnTo = async (sessionId: string) => void this.calls.push(`turn ${sessionId}`);
  card = async (card: { title: string; sessionId?: string }) => void this.calls.push(`card ${card.title} ${card.sessionId ?? 'none'}`);
  board = async (title: string) => void this.calls.push(`board ${title}`);
  walk = async (walk: { pages: readonly unknown[] }) => void this.calls.push(`walk ${walk.pages.length}`);
  trace = async (_trace: unknown, title: string) => void this.calls.push(`trace ${title}`);
  dismissAll = async () => void this.calls.push('dismiss');
  openFolder = async (path: string) => (this.calls.push(`folder ${path}`), this.opens);
  openLink = async (url: string) => (this.calls.push(`link ${url}`), this.opens);
}

const show = (display: string, extra: Partial<DaemonEvent> = {}): DaemonEvent => ({ kind: 'show', display: display as DaemonEvent['display'], subject: 'shw_1', agent: 'claude-code', summary: 'it', at: minutesAgo(0), ...extra });

describe('what the daemon asks to show', () => {
  const delivered = { delivered: (request: { id: number }) => [{ id: request.id, ok: true }], seen: (request: { id: number }) => [{ id: request.id, ok: true }] };

  it('opens a live window, a card, a board, a walk and a trace', async () => {
    const presenter = new RecordingPresenter();
    const displays = new Displays(new ScriptedDaemon(delivered), new RequestIds(), presenter);
    await displays.handle(show('open', { sessionId: 'ses_1' }));
    await displays.handle(show('card', { title: 'Pull requests', sessionId: 'all' }));
    await displays.handle(show('sessions'));
    await displays.handle(show('walk', { pages: [{ path: 'a', note: 'b', lines: [] }] }));
    await displays.handle(show('trace', { trace: { totalMs: 1, rows: [] } }));
    await displays.handle(show('dismiss'));
    expect(presenter.calls).toEqual(['live ses_1', 'card Pull requests none', 'board Your sessions', 'walk 1', 'trace Trace', 'dismiss']);
  });

  it('tells the daemon what it cannot do here, so the voice never says it was done', async () => {
    const link = new ScriptedDaemon(delivered);
    const displays = new Displays(link, new RequestIds(), new RecordingPresenter());
    await displays.handle(show('type', { sessionId: 'ses_1' }));
    await displays.handle(show('focus', { sessionId: 'ses_1' }));
    expect(link.sent('delivered').map((request) => request.answer)).toEqual(['failed', 'failed']);
    expect(link.sent('delivered')[0]?.reason).toContain('cannot type');
  });

  it('opens only a web link, and says so either way', async () => {
    const link = new ScriptedDaemon(delivered);
    const presenter = new RecordingPresenter();
    const displays = new Displays(link, new RequestIds(), presenter);
    await displays.handle(show('link', { app: { links: ['https://memnox.com/docs'] } }));
    await displays.handle(show('link', { app: { links: ['file:///etc/passwd'] } }));
    expect(presenter.calls).toEqual(['link https://memnox.com/docs']);
    expect(link.sent('delivered').map((request) => request.answer)).toEqual(['typed', 'failed']);
  });

  it('answers a look with nothing seen rather than leaving the brain waiting', async () => {
    const link = new ScriptedDaemon(delivered);
    await new Displays(link, new RequestIds(), new RecordingPresenter()).handle(show('look', { title: 'Firefox' }));
    expect(link.sent('seen')[0]?.sight).toEqual({ app: 'Firefox' });
  });
});

describe('the gesture an event earns', () => {
  it('bursts only for tests that passed and stumbles for a pause or a collision', () => {
    const notice = (word: string, tests?: string): DaemonEvent => ({ kind: 'notice', notice: word, tests: tests as DaemonEvent['tests'], subject: 's', agent: 'a', summary: '', at: '' });
    expect(reactionTo(notice('finished', 'passed'))).toBe('burst');
    expect(reactionTo(notice('finished', 'stale'))).toBe('settle');
    expect(reactionTo(notice('collision'))).toBe('stumble');
    expect(reactionTo({ ...notice('x'), kind: 'paused' })).toBe('stumble');
    expect(reactionTo(notice('question'))).toBeUndefined();
  });
});

describe('the history of what was asked', () => {
  it('drops an exchange that got no words and keeps a failure to ask again', () => {
    let history = ask(NO_HISTORY, 'what changed', NOW, 'e1');
    history = end(history, NOW + 1_000);
    expect(history.exchanges).toHaveLength(0);
    history = ask(history, 'what changed', NOW, 'e2');
    history = end(history, NOW + 1_000, 'Memnox did not answer');
    expect(history.exchanges[0]?.failure).toBe('Memnox did not answer');
  });

  it('groups by day, newest first, and reads back leniently', () => {
    let history = ask(NO_HISTORY, 'first', NOW - 2 * 86_400_000, 'e1');
    history = end(replied(history, 'yes'), NOW - 2 * 86_400_000 + 1_000);
    history = ask(history, 'second', NOW, 'e2');
    history = end(replied(history, 'done'), NOW + 3_200);
    const days = historyDays(history, '', NOW);
    expect(days).toHaveLength(2);
    expect(days[0]?.title.startsWith('Today')).toBe(true);
    expect(historyDays(history, 'FIRST', NOW)).toHaveLength(1);
    expect(exchangeDetail(history.exchanges[0]!, NOW)).toMatch(/^Answered in 3\.2s/);
    expect(parseHistory('not json')).toEqual(NO_HISTORY);
    expect(parseHistory(JSON.stringify(history)).exchanges).toHaveLength(2);
  });

  it('follows the voice: heard words start an exchange, the reply grows it and quiet ends it', () => {
    let kept: string | null = null;
    const store: HistoryStore = { load: () => kept, save: (text) => (kept = text) };
    let state: TalkState = { phase: 'idle', heard: undefined, reply: '', failure: undefined };
    const listeners: (() => void)[] = [];
    const keeper = new HistoryKeeper(store, () => 'id1', () => NOW);
    keeper.follow({ get state() { return state; }, observe: (listener) => (listeners.push(listener), () => undefined) });
    const go = (next: Partial<TalkState>) => {
      state = { ...state, ...next };
      for (const listener of listeners) listener();
    };
    go({ phase: 'thinking', heard: 'what is running' });
    go({ phase: 'speaking', reply: 'Two sessions.' });
    go({ phase: 'idle' });
    expect(keeper.history.exchanges[0]).toMatchObject({ question: 'what is running', answer: 'Two sessions.', answeredAt: NOW });
    expect(parseHistory(kept).exchanges).toHaveLength(1);
  });
});
