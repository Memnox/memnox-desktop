import type { Delivery, DisplayHost } from '@memnox/core/wire';
import type { EditorKind, TerminalKind, TerminalPane } from '../../domain/session-focus';

/** How a display that acts on another app ended, in the runtime's DELIVERY words, with why when it did not. */
export interface Shown {
  readonly answer: Delivery;
  readonly reason?: string;
}

/**
 * Each tool's own documented controls, as this computer reaches them: a terminal's command line to list
 * and focus its panes or open a tab, an editor's command line and the Memnox extension's links, and the
 * URL handler for an agent app's own links. Each rejects, or answers failed, with a reason the voice can say.
 */
export interface Terminals {
  /** The panes the terminal lists, or a rejection saying why it cannot, such as its remote control being off. */
  panes(terminal: TerminalKind): Promise<readonly TerminalPane[]>;
  /** Brings one listed pane forward by the terminal's own command. */
  focusPane(terminal: TerminalKind, pane: TerminalPane): Promise<void>;
  /** The editor on the session's folder, and the conversation or terminal in it where its link can say which. */
  focusEditor(host: DisplayHost): Promise<Shown>;
  /** A new tab in a supported terminal, in the folder, running the runtime's line as it was sent. */
  launchInTerminal(terminal: TerminalKind | undefined, line: string, folder: string, background: boolean): Promise<Shown>;
  /** The editor on the folder, then the Memnox extension's launch link, answered once the extension writes back. */
  launchInEditor(editor: EditorKind, folder: string, request: string): Promise<Shown>;
  /** An agent app's own links, a moment apart, through the system's URL handler. */
  openAppLinks(links: readonly string[]): Promise<Shown>;
}
