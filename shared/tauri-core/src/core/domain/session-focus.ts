import type { DisplayHost } from '@memnox/core/wire';
import { bestTab } from './tab-match';
import { isAgentProgram } from './terminal-front';

/**
 * Where a session runs and how this computer may bring it forward, kept to each tool's own documented
 * controls: an editor through its command line and the Memnox extension's link, and a terminal through
 * its own command line, which lists its panes and focuses one. Nothing raises another app's window by
 * itself, presses a key in it or reads its screen.
 */

/** The terminals whose own command line lists and focuses their panes or opens a tab. */
export const TERMINAL = {
  WEZTERM: 'wezterm',
  KITTY: 'kitty',
  WINDOWS_TERMINAL: 'windows-terminal',
} as const;

export type TerminalKind = (typeof TERMINAL)[keyof typeof TERMINAL];

/** Every terminal whose panes can be listed, in the order they are asked when the host names none. */
export const LISTING_TERMINALS: readonly TerminalKind[] = [TERMINAL.WEZTERM, TERMINAL.KITTY];

/** The editors the Memnox extension runs in, VS Code and the editors built on it. */
export const EDITOR = {
  CODE: 'code',
  CURSOR: 'cursor',
  WINDSURF: 'windsurf',
} as const;

export type EditorKind = (typeof EDITOR)[keyof typeof EDITOR];

/** One pane a terminal's own listing gave, with an id only that terminal reads. */
export interface TerminalPane {
  readonly id: string;
  readonly title: string;
  readonly cwd?: string;
  readonly tty?: string;
  /** The programs in front in it, by path, where the terminal says. */
  readonly programs: readonly string[];
}

/** The app's name lowercased, from its name or else its path. */
function appName(host: DisplayHost | undefined): string {
  return (host?.app ?? host?.appPath ?? '').toLowerCase();
}

/** The editor an app name or path names; Cursor and Windsurf first, since both are built on Code. */
export function editorNamed(name: string): EditorKind | undefined {
  const lowered = name.toLowerCase();
  if (lowered.includes('cursor')) return EDITOR.CURSOR;
  if (lowered.includes('windsurf')) return EDITOR.WINDSURF;
  const program = lowered.split(/[/\\]/).pop() ?? '';
  if (lowered.includes('visual studio code') || lowered.includes('vscode') || /^code(\.exe|\.cmd)?$/.test(program) || lowered.startsWith('code ')) return EDITOR.CODE;
  return undefined;
}

/** The editor a session runs in, when the runtime noted one. */
export function editorOf(host: DisplayHost | undefined): EditorKind | undefined {
  return editorNamed(appName(host));
}

/** The terminal an app name or path names, when it is one whose own command line this computer drives. */
export function terminalNamed(name: string): TerminalKind | undefined {
  const lowered = name.toLowerCase();
  if (lowered.includes('wezterm')) return TERMINAL.WEZTERM;
  if (lowered.includes('kitty')) return TERMINAL.KITTY;
  if (lowered.includes('windows terminal') || lowered.includes('windowsterminal') || /(^|[/\\])wt(\.exe)?$/.test(lowered)) return TERMINAL.WINDOWS_TERMINAL;
  return undefined;
}

export function terminalOf(host: DisplayHost | undefined): TerminalKind | undefined {
  return terminalNamed(appName(host));
}

/** As a person names it. */
export function terminalTitle(terminal: TerminalKind): string {
  switch (terminal) {
    case TERMINAL.WEZTERM:
      return 'WezTerm';
    case TERMINAL.KITTY:
      return 'kitty';
    case TERMINAL.WINDOWS_TERMINAL:
      return 'Windows Terminal';
  }
}

/**
 * A folder as one comparable string: a `file://host` prefix gone, as WezTerm reports it, forward slashes,
 * no trailing slash, and lowercase on a drive path, since Windows reads its paths without case.
 */
export function folderKey(path: string | undefined): string | undefined {
  if (path === undefined) return undefined;
  let folder = path.trim();
  const url = /^file:\/\/[^/]*(\/.*)$/i.exec(folder);
  if (url?.[1] !== undefined) folder = decodeURIComponent(url[1]);
  folder = folder.replace(/\\/g, '/');
  // A Windows drive as a URL writes it /C:/Users, which is C:/Users on disk.
  if (/^\/[a-z]:\//i.test(folder)) folder = folder.slice(1);
  folder = folder.replace(/\/+$/, '');
  if (folder === '') return undefined;
  return /^[a-z]:/i.test(folder) ? folder.toLowerCase() : folder;
}

/** A terminal device as one comparable name, `pts/3` and `/dev/pts/3` alike. */
export function deviceKey(tty: string | undefined): string | undefined {
  const name = tty?.trim().replace(/^\/dev\//, '');
  return name === undefined || name === '' || name === '?' || name === '??' ? undefined : name;
}

export type PaneChoice = { readonly pane: TerminalPane } | { readonly why: string };

/**
 * The pane a session runs in among one terminal's panes: the one on its device when both are known;
 * else the one whose title and folder show the most of its lines, with TabMatch; else the only one in its
 * folder, or the only one there with an agent in front. Two equally likely is no answer, since bringing
 * the wrong agent forward is worse than saying which could not be told.
 */
export function choosePane(panes: readonly TerminalPane[], host: DisplayHost, terminal: string): PaneChoice {
  if (panes.length === 0) return { why: `${terminal} has no tabs open` };
  const device = deviceKey(host.tty);
  if (device !== undefined) {
    const onDevice = panes.find((pane) => deviceKey(pane.tty) === device);
    if (onDevice !== undefined) return { pane: onDevice };
  }
  const marks = host.marks ?? [];
  const best = bestTab(
    panes.map((pane) => `${pane.title}\n${pane.cwd ?? ''}`),
    marks,
  );
  if (best !== undefined && panes[best] !== undefined) return { pane: panes[best] };
  const folder = folderKey(host.cwd);
  if (folder === undefined) return { why: `where it runs in ${terminal} was never noted, so its tab cannot be told from the others` };
  const inFolder = panes.filter((pane) => folderKey(pane.cwd) === folder);
  const only = inFolder.length === 1 ? inFolder[0] : undefined;
  if (only !== undefined) return { pane: only };
  if (inFolder.length === 0) return { why: `no tab in ${terminal} is in its folder` };
  const withAgent = inFolder.filter((pane) => pane.programs.some(isAgentProgram));
  const agent = withAgent.length === 1 ? withAgent[0] : undefined;
  if (agent !== undefined) return { pane: agent };
  return { why: `${inFolder.length} tabs in ${terminal} are in its folder, so which one is the session's cannot be told` };
}

/** The Claude Code extension's conversation id is a UUID, the only id that opens its conversation rather than a new one. */
export function isConversationId(id: string | undefined): boolean {
  return id !== undefined && /^[0-9a-f-]{36}$/i.test(id);
}

/** The schemes an agent's own desktop app answers on, the only links an APP display may open. */
const APP_SCHEMES: readonly string[] = ['claude', 'codex', 'cursor', 'vscode', 'windsurf'];

/** Whether a link is one of an agent app's own, with nothing in it a shell could read as a second command. */
export function isAppLink(link: string): boolean {
  const match = /^([a-z][a-z0-9+.-]*):\/\/(.+)$/i.exec(link);
  const scheme = match?.[1]?.toLowerCase();
  return scheme !== undefined && APP_SCHEMES.includes(scheme) && !/[\s"\u0000-\u001f\u007f]/.test(link);
}

/** How a LAUNCH reaches where it starts, decided before anything is opened. */
export type LaunchPlan =
  | { readonly kind: 'editor'; readonly editor: EditorKind; readonly app: string }
  | { readonly kind: 'terminal'; readonly terminal?: TerminalKind; readonly background: boolean }
  | { readonly kind: 'none'; readonly why: string };

/** The terminals that open a tab without bringing their window forward, so Stay where I am keeps the person's window. */
export const BACKGROUND_TERMINALS: readonly TerminalKind[] = [TERMINAL.WEZTERM, TERMINAL.KITTY];

/**
 * Where a LAUNCH starts: in the editor the runtime named, through the Memnox extension; in the terminal it
 * named; or in a new tab of whichever supported terminal is here. With Stay where I am on, only a terminal
 * that opens a tab behind is used, and anything that would take the person's window says it cannot.
 */
export function launchPlan(app: string | undefined, viaTerminalApp: boolean, stayPut: boolean): LaunchPlan {
  const editor = app === undefined || viaTerminalApp ? undefined : editorNamed(app);
  if (editor !== undefined && app !== undefined) {
    if (stayPut) return { kind: 'none', why: 'Stay where I am is on, and starting it in the editor would bring the editor forward, so nothing was started' };
    return { kind: 'editor', editor, app };
  }
  const terminal = app === undefined ? undefined : terminalNamed(app);
  if (viaTerminalApp && terminal === undefined) return { kind: 'none', why: 'that terminal has no command line this computer can start a tab through; WezTerm, kitty and Windows Terminal do' };
  if (stayPut && terminal !== undefined && !BACKGROUND_TERMINALS.includes(terminal))
    return { kind: 'none', why: `Stay where I am is on, and ${terminalTitle(terminal)} brings its window forward to open a tab, so nothing was started` };
  return { kind: 'terminal', ...(terminal === undefined ? {} : { terminal }), background: stayPut };
}
