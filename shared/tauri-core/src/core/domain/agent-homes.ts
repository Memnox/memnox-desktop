import type { Platform } from './platform';
import { BACKGROUND_TERMINALS, EDITOR, TERMINAL, terminalTitle, type EditorKind, type LaunchPlan, type TerminalKind } from './session-focus';

/**
 * Where the person runs their agents, as the Mac's `AgentHomes`: the terminal or editor a new session opens in,
 * picked from those installed here. Windows and Linux need none of the Automation and Accessibility switches the
 * Mac asks for, so those rows are left out and every other word stays the Mac's.
 */

export type AgentHomeKind = 'windows-terminal' | 'powershell' | 'cmd' | 'gnome-terminal' | 'konsole' | 'kitty' | 'alacritty' | 'xterm' | 'vscode';

/** As a person names each, and whether it is the editor rather than a terminal. */
export const AGENT_HOMES: Readonly<Record<AgentHomeKind, { readonly name: string; readonly editor: boolean }>> = {
  'windows-terminal': { name: 'Windows Terminal', editor: false },
  powershell: { name: 'PowerShell', editor: false },
  cmd: { name: 'Command Prompt', editor: false },
  'gnome-terminal': { name: 'GNOME Terminal', editor: false },
  konsole: { name: 'Konsole', editor: false },
  kitty: { name: 'kitty', editor: false },
  alacritty: { name: 'Alacritty', editor: false },
  xterm: { name: 'xterm', editor: false },
  vscode: { name: 'VS Code', editor: true },
};

/** One app Rust found here, with the editor's two checks where it is the editor. */
export interface FoundHome {
  readonly kind: AgentHomeKind;
  readonly memnoxExtension?: boolean;
  readonly claudeCode?: boolean;
}

export function isAgentHome(value: string | null | undefined): value is AgentHomeKind {
  return value !== null && value !== undefined && Object.hasOwn(AGENT_HOMES, value);
}

/** The keys the choice is kept under, the Mac's UserDefaults keys under the app's prefix. */
export const AGENT_HOME_KEYS = {
  chosen: 'memnox.agentHomes',
  /** Kept apart from the choice since a cleared choice is not the same as one never made. */
  answered: 'memnox.agentHomesAnswered',
  chatOpened: 'memnox.agentHomesChatOpened',
} as const;

/**
 * The app a session opens in: the one kept when it is still installed, nothing once the person cleared it, and until
 * they answer the first installed, since most people use what they installed, as the Mac offers it ticked.
 */
export function chosenHome(kept: string | null, answered: boolean, installed: readonly AgentHomeKind[]): AgentHomeKind | undefined {
  if (isAgentHome(kept)) return installed.includes(kept) ? kept : undefined;
  return answered ? undefined : installed[0];
}

/** How a session reaches the picked app: the editor through the Memnox extension, a terminal through its own command line, or a window of its own. */
export type HomeLaunch =
  | { readonly kind: 'editor'; readonly editor: EditorKind }
  | { readonly kind: 'terminal'; readonly terminal: TerminalKind }
  | { readonly kind: 'window'; readonly home: AgentHomeKind };

export function homeLaunch(home: AgentHomeKind): HomeLaunch {
  switch (home) {
    case 'vscode':
      return { kind: 'editor', editor: EDITOR.CODE };
    case 'windows-terminal':
      return { kind: 'terminal', terminal: TERMINAL.WINDOWS_TERMINAL };
    case 'powershell':
    case 'cmd':
    case 'gnome-terminal':
    case 'konsole':
    case 'kitty':
    case 'alacritty':
    case 'xterm':
      return { kind: 'window', home };
  }
}

/**
 * Where a session the runtime named no app for starts, once the person picked one: in it, or nowhere with why while
 * Stay where I am is on and opening it would take the person's window, in the words the runtime's own plan uses.
 */
export function pickedPlan(home: AgentHomeKind, stayPut: boolean): LaunchPlan {
  const reach = homeLaunch(home);
  switch (reach.kind) {
    case 'editor':
      if (stayPut) return { kind: 'none', why: 'Stay where I am is on, and starting it in the editor would bring the editor forward, so nothing was started' };
      return { kind: 'editor', editor: reach.editor, app: AGENT_HOMES[home].name };
    case 'terminal':
      if (stayPut && !BACKGROUND_TERMINALS.includes(reach.terminal))
        return { kind: 'none', why: `Stay where I am is on, and ${terminalTitle(reach.terminal)} brings its window forward to open a tab, so nothing was started` };
      return { kind: 'terminal', terminal: reach.terminal, background: stayPut };
    case 'window':
      if (stayPut) return { kind: 'none', why: `Stay where I am is on, and ${AGENT_HOMES[home].name} opens its window in front, so nothing was started` };
      return { kind: 'window', home };
  }
}

/** Whether everything the app needs is in, for its tick: the editor's extension and its chat, and nothing more for a terminal here. */
export function homeReady(found: FoundHome, chatOpened: boolean): boolean {
  if (!AGENT_HOMES[found.kind].editor) return true;
  const chat = found.claudeCode !== true || chatOpened;
  return found.memnoxExtension === true && chat;
}

/** The apps each system offers, named in the empty row. */
const WORKS_WITH: Readonly<Record<Platform, string>> = {
  windows: 'Memnox works with Windows Terminal, PowerShell, Command Prompt and VS Code.',
  linux: 'Memnox works with GNOME Terminal, Konsole, kitty, Alacritty, xterm and VS Code.',
  other: 'Memnox works with VS Code and the terminals on this computer.',
};

/** The Where your agents run section's words, the Mac's own, its macOS permission rows left out. */
export const AgentHomesLines = {
  section: 'Where your agents run',
  yourApps: 'Your apps',
  noneTitle: 'No editor or terminal found',
  noneDetail: (platform: Platform) => WORKS_WITH[platform],
  /** Said on the Your apps card: what to do, or how many of the apps picked are ready. */
  picked: (chosen: number, ready: number) => {
    if (chosen === 0) return 'Tap the one you run Claude Code, Codex or Cursor in.';
    return ready === chosen ? 'All set in the app you picked.' : `${ready} of ${chosen} ready.`;
  },
  chosenHint: 'New sessions open here',
  otherHint: 'Tap so new sessions open here',
  ready: 'Ready.',
  editorSummary: 'So Memnox can start a session, follow up in its chat and reach the terminal a session runs in.',
  extension: 'Memnox extension',
  extensionIn: 'In, so your voice reaches the terminal a session runs in.',
  extensionComing: 'The Memnox service puts it in on its own once it is running.',
  claudeIn: (name: string) => `Claude Code in ${name}`,
  claudeMissing: 'Add the Claude Code extension, so Memnox can start sessions in its chat and follow up there.',
  getIt: 'Get it',
  didChatOpen: 'Did Claude Code’s chat open?',
  didChatOpenDetail: (name: string) => `If ${name} asked whether Claude Code may open the link, tick Don’t ask again, then press Open.`,
  notYet: 'Not yet',
  itOpened: 'It opened',
  openChats: 'Open chats from Memnox',
  chatsOpen: 'Memnox opens the Claude Code chat a session runs in, and starts new ones there.',
  chatsAsk: (name: string) => `${name} asks once before it lets a link open Claude Code. Try it now so it never asks mid task.`,
  tryIt: 'Try it',
} as const;

/** The link that opens Claude Code's chat in VS Code, the same one a follow up opens. */
export const CLAUDE_CHAT_LINK = 'vscode://anthropic.claude-code/open';
/** Where Claude Code's extension is offered, for an editor that does not have it yet. */
export const CLAUDE_EXTENSION_PAGE = 'https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code';
