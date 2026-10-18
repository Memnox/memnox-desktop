import type { DaemonEvent, DisplayHost } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { CANNOT, Displays, type Presenter } from '../src/core/application/displays';
import type { Shown, Terminals } from '../src/core/application/ports/terminals';
import { RequestIds } from '../src/core/application/request-ids';
import { NO_TERMINAL_CONTROL, SessionFocus } from '../src/core/application/session-focus';
import { choosePane, folderKey, isAppLink, launchPlan, terminalNamed, type TerminalKind, type TerminalPane } from '../src/core/domain/session-focus';
import { bestTab, isCertainTab } from '../src/core/domain/tab-match';
import { agentInFront, isAgentProgram } from '../src/core/domain/terminal-front';
import { ScriptedDaemon } from './doubles';

describe('TabMatch', () => {
  it('finds the one tab showing most of the session and none when two tie', () => {
    const marks = ['Fix the login page', 'ses_12'];
    const texts = ['$ ls\nREADME', '> Fix the login\n page\nses_12', 'Fix the login page'];
    expect(bestTab(texts, marks)).toBe(1);
    expect(isCertainTab(texts[1] ?? '', marks)).toBe(true);
    expect(isCertainTab(texts[2] ?? '', marks)).toBe(false);
    expect(bestTab(['ses_12', 'ses_12'], marks)).toBeUndefined();
    expect(bestTab(['nothing'], marks)).toBeUndefined();
    expect(bestTab(texts, [])).toBeUndefined();
    expect(bestTab(texts, ['  '])).toBeUndefined();
  });
});

describe('TerminalFront', () => {
  it('knows an agent by its program or its versioned folder', () => {
    expect(isAgentProgram('/usr/local/bin/claude')).toBe(true);
    expect(isAgentProgram('C:\\Users\\a\\codex.exe')).toBe(true);
    expect(isAgentProgram('/home/a/.local/share/claude/versions/2.1.3')).toBe(true);
    expect(isAgentProgram('/usr/bin/zsh')).toBe(false);
    expect(isAgentProgram('/usr/lib/node/lib/tool')).toBe(false);
    expect(isAgentProgram('')).toBe(false);
  });

  it('reads only the program marked in front', () => {
    expect(agentInFront('Ss   -zsh\nS+   claude\n')).toBe(true);
    expect(agentInFront('S+   -zsh\nS    claude\n')).toBe(false);
    expect(agentInFront('S+\n')).toBe(false);
  });
});

const pane = (id: string, cwd: string | undefined, extra: Partial<TerminalPane> = {}): TerminalPane => ({ id, title: 'zsh', programs: [], ...(cwd === undefined ? {} : { cwd }), ...extra });

describe('choosing the pane a session runs in', () => {
  it('takes the pane on its device first', () => {
    const panes = [pane('1', '/a'), pane('2', '/a', { tty: '/dev/pts/4' })];
    expect(choosePane(panes, { tty: 'pts/4', cwd: '/a' }, 'WezTerm')).toEqual({ pane: panes[1] });
  });

  it('takes the pane whose title shows the most of its lines', () => {
    const panes = [pane('1', '/a', { title: 'zsh' }), pane('2', '/a', { title: '✳ Fix the login page' })];
    expect(choosePane(panes, { cwd: '/a', marks: ['Fix the login page'] }, 'kitty')).toEqual({ pane: panes[1] });
  });

  it('takes the only pane in its folder, however the terminal writes the folder', () => {
    const panes = [pane('1', 'file://box/home/a/web'), pane('2', 'file://box/home/a/shop/')];
    expect(choosePane(panes, { cwd: '/home/a/shop' }, 'WezTerm')).toEqual({ pane: panes[1] });
    expect(folderKey('file://box/C:/Users/A/shop')).toBe('c:/users/a/shop');
    expect(folderKey('C:\\Users\\a\\Shop\\')).toBe('c:/users/a/shop');
    expect(folderKey('file:///home/a/my%20shop')).toBe('/home/a/my shop');
  });

  it('takes the one with an agent in front when two share its folder, and says so when that cannot tell them apart', () => {
    const panes = [pane('1', '/a', { programs: ['/bin/zsh'] }), pane('2', '/a', { programs: ['/home/a/.local/bin/claude'] })];
    expect(choosePane(panes, { cwd: '/a' }, 'kitty')).toEqual({ pane: panes[1] });
    const twins = [pane('1', '/a'), pane('2', '/a')];
    expect(choosePane(twins, { cwd: '/a' }, 'kitty')).toEqual({ why: "2 tabs in kitty are in its folder, so which one is the session's cannot be told" });
    expect(choosePane([pane('1', '/b')], { cwd: '/a' }, 'kitty')).toEqual({ why: 'no tab in kitty is in its folder' });
    expect(choosePane([], { cwd: '/a' }, 'kitty')).toEqual({ why: 'kitty has no tabs open' });
  });
});

describe('where a launch starts', () => {
  it('starts in the editor the runtime named, unless Stay where I am is on', () => {
    expect(launchPlan('/usr/share/code/code', false, false)).toEqual({ kind: 'editor', editor: 'code', app: '/usr/share/code/code' });
    expect(launchPlan('C:\\Program Files\\Cursor\\Cursor.exe', false, true).kind).toBe('none');
  });

  it('starts in a terminal tab, and with Stay where I am on only in one that opens it behind', () => {
    expect(launchPlan(undefined, false, true)).toEqual({ kind: 'terminal', background: true });
    expect(launchPlan('/usr/bin/kitty', true, false)).toEqual({ kind: 'terminal', terminal: 'kitty', background: false });
    expect(launchPlan('wt.exe', true, true)).toEqual({ kind: 'none', why: 'Stay where I am is on, and Windows Terminal brings its window forward to open a tab, so nothing was started' });
    expect(launchPlan('/usr/bin/ghostty', true, false).kind).toBe('none');
    expect(terminalNamed('C:\\Program Files\\WezTerm\\wezterm-gui.exe')).toBe('wezterm');
  });

  it('opens only an agent app link', () => {
    expect(isAppLink('claude://code/new?folder=%2Ftmp')).toBe(true);
    expect(isAppLink('https://example.com')).toBe(false);
    expect(isAppLink('file:///etc/passwd')).toBe(false);
    expect(isAppLink('claude://x y')).toBe(false);
    expect(isAppLink('claude://')).toBe(false);
  });
});

/** Terminals that answer as scripted, and remember what they were asked. */
class ScriptedTerminals implements Terminals {
  readonly asked: string[] = [];
  constructor(
    private readonly listed: Partial<Record<TerminalKind, readonly TerminalPane[] | string>> = {},
    private readonly answers: Partial<Record<'editor' | 'terminal' | 'launchEditor' | 'app', Shown>> = {},
  ) {}
  async panes(terminal: TerminalKind) {
    this.asked.push(`list ${terminal}`);
    const listed = this.listed[terminal];
    if (listed === undefined) throw `${terminal} is not installed here`;
    if (typeof listed === 'string') throw listed;
    return listed;
  }
  async focusPane(terminal: TerminalKind, pane: TerminalPane) {
    this.asked.push(`focus ${terminal} ${pane.id}`);
  }
  async focusEditor(host: DisplayHost) {
    this.asked.push(`editor ${host.cwd ?? ''}`);
    return this.answers.editor ?? { answer: 'typed' as const };
  }
  async launchInTerminal(terminal: TerminalKind | undefined, line: string, folder: string, background: boolean) {
    this.asked.push(`launch ${terminal ?? 'any'} ${folder} ${background ? 'behind' : 'front'} ${line}`);
    return this.answers.terminal ?? { answer: 'typed' as const };
  }
  async launchInEditor(editor: string, folder: string, request: string) {
    this.asked.push(`launch ${editor} ${folder} ${request}`);
    return this.answers.launchEditor ?? { answer: 'typed' as const };
  }
  async openAppLinks(links: readonly string[]) {
    this.asked.push(`app ${links.join(' ')}`);
    return this.answers.app ?? { answer: 'typed' as const };
  }
}

describe('bringing a session forward', () => {
  it('brings an editor session forward through the editor', async () => {
    const terminals = new ScriptedTerminals();
    expect(await new SessionFocus(terminals).focus({ app: 'Cursor', cwd: '/a' })).toEqual({ answer: 'typed' });
    expect(terminals.asked).toEqual(['editor /a']);
  });

  it('lists the terminal it runs in and focuses the pane TabMatch picks', async () => {
    const terminals = new ScriptedTerminals({ wezterm: [pane('7', '/b'), pane('8', 'file://box/a')] });
    expect(await new SessionFocus(terminals).focus({ app: 'WezTerm', cwd: '/a' })).toEqual({ answer: 'typed' });
    expect(terminals.asked).toEqual(['list wezterm', 'focus wezterm 8']);
  });

  it("says why when the terminal's remote control is off", async () => {
    const terminals = new ScriptedTerminals({ kitty: "kitty's remote control is off" });
    expect(await new SessionFocus(terminals).focus({ app: 'kitty', cwd: '/a' })).toEqual({ answer: 'failed', reason: "kitty's remote control is off" });
  });

  it('never focuses another terminal for a session in one it cannot drive', async () => {
    const terminals = new ScriptedTerminals({ wezterm: [pane('7', '/a')] });
    const shown = await new SessionFocus(terminals).focus({ app: 'GNOME Terminal', cwd: '/a' });
    expect(shown.answer).toBe('failed');
    expect(shown.reason).toContain('GNOME Terminal has no command line');
    expect(terminals.asked).toEqual([]);
  });

  it('asks every terminal it drives when the app was never noted, and says none could', async () => {
    const terminals = new ScriptedTerminals();
    expect(await new SessionFocus(terminals).focus({ cwd: '/a' })).toEqual({ answer: 'failed', reason: NO_TERMINAL_CONTROL });
    expect(terminals.asked).toEqual(['list wezterm', 'list kitty']);
    expect((await new SessionFocus(terminals).focus({ app: 'Windows Terminal', cwd: '/a' })).reason).toContain('cannot list its tabs');
    expect((await new SessionFocus(terminals).focus(undefined)).reason).toContain('never noted');
  });
});

class FocusingPresenter implements Presenter {
  readonly calls: string[] = [];
  constructor(private readonly shown: Shown) {}
  live = async (sessionId: string) => void this.calls.push(`live ${sessionId}`);
  focus = async (sessionId: string) => (this.calls.push(`focus ${sessionId}`), this.shown);
  card = async () => undefined;
  board = async () => undefined;
  walk = async () => undefined;
  trace = async () => undefined;
  dismissAll = async () => undefined;
  openFolder = async () => true;
  openLink = async () => true;
}

const show = (display: string, extra: Partial<DaemonEvent> = {}): DaemonEvent => ({ kind: 'show', display: display as DaemonEvent['display'], subject: 'shw_1', agent: 'claude-code', summary: 'it', at: '', ...extra });
const answering = { delivered: (request: { id: number }) => [{ id: request.id, ok: true }] };

describe('what the daemon asks to bring forward or start', () => {
  it('reports how bringing a session forward ended', async () => {
    const link = new ScriptedDaemon(answering);
    const presenter = new FocusingPresenter({ answer: 'typed' });
    await new Displays(link, new RequestIds(), presenter).handle(show('focus', { sessionId: 'ses_1', host: { app: 'WezTerm' } }));
    expect(presenter.calls).toEqual(['focus ses_1']);
    expect(link.sent('delivered')[0]?.answer).toBe('typed');
  });

  it('starts an agent in a terminal tab with the exact line, behind when Stay where I am is on', async () => {
    const link = new ScriptedDaemon(answering);
    const terminals = new ScriptedTerminals();
    const displays = new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' }), { terminals, stayPut: () => true });
    await displays.handle(show('launch', { summary: "cd '/a' && memnox run claude 'fix it'", host: { cwd: '/a' } }));
    expect(terminals.asked).toEqual(["launch any /a behind cd '/a' && memnox run claude 'fix it'"]);
    expect(link.sent('delivered')[0]?.answer).toBe('typed');
  });

  it('starts one in an editor through the Memnox extension, by the request', async () => {
    const link = new ScriptedDaemon(answering);
    const terminals = new ScriptedTerminals({}, { launchEditor: { answer: 'failed', reason: 'the Memnox extension did not answer' } });
    const displays = new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' }), { terminals, stayPut: () => false });
    await displays.handle(show('launch', { subject: 'dsp_9', host: { cwd: '/a', appPath: '/usr/share/code/code' } }));
    expect(terminals.asked).toEqual(['launch code /a dsp_9']);
    expect(link.sent('delivered')[0]).toMatchObject({ answer: 'failed', reason: 'the Memnox extension did not answer' });
  });

  it('starts nothing without a folder, in an agent panel, or with no terminals reached', async () => {
    const link = new ScriptedDaemon(answering);
    const terminals = new ScriptedTerminals();
    const displays = new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' }), { terminals });
    await displays.handle(show('launch', { host: {} }));
    await displays.handle(show('launch', { via: 'panel', host: { cwd: '/a' } }));
    await new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' })).handle(show('launch', { host: { cwd: '/a' } }));
    expect(terminals.asked).toEqual([]);
    expect(link.sent('delivered').map((request) => request.reason)).toEqual(['the repository folder is not known, so there is nowhere to start it', CANNOT.panel, CANNOT.launch]);
  });

  it("opens an agent's app only by its own links, and says the words were not put in", async () => {
    const link = new ScriptedDaemon(answering);
    const terminals = new ScriptedTerminals();
    const displays = new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' }), { terminals });
    await displays.handle(show('app', { title: 'Claude', summary: 'Claude', app: { links: ['claude://code/new'] } }));
    await displays.handle(show('app', { title: 'Claude', summary: 'fix the tests', app: { links: ['claude://code/new'] } }));
    await displays.handle(show('app', { title: 'Claude', app: { links: ['file:///etc/passwd'] } }));
    expect(terminals.asked).toEqual(['app claude://code/new', 'app claude://code/new']);
    const answers = link.sent('delivered');
    expect(answers.map((request) => request.answer)).toEqual(['typed', 'failed', 'failed']);
    expect(answers[1]?.reason).toContain('the words were not put in');
    expect(answers[2]?.reason).toContain('no link of its own');
  });

  it('answers every keystroke display failed with a reason the voice can say', async () => {
    const link = new ScriptedDaemon(answering);
    const displays = new Displays(link, new RequestIds(), new FocusingPresenter({ answer: 'typed' }), { terminals: new ScriptedTerminals() });
    for (const display of ['type', 'prefill', 'close', 'interrupt', 'press']) await displays.handle(show(display, { sessionId: 'ses_1' }));
    const answers = link.sent('delivered');
    expect(answers.map((request) => request.answer)).toEqual(['failed', 'failed', 'failed', 'failed', 'failed']);
    for (const request of answers) expect(request.reason).toMatch(/^this computer does not /);
  });
});
