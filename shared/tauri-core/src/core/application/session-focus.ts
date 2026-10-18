import { DELIVERY, type DisplayHost } from '@memnox/core/wire';
import { choosePane, editorOf, LISTING_TERMINALS, TERMINAL, terminalOf, terminalTitle, type TerminalKind } from '../domain/session-focus';
import type { Shown, Terminals } from './ports/terminals';

/** Said when no supported terminal answered, since that is the one thing the person can change. */
export const NO_TERMINAL_CONTROL =
  "no terminal here lets Memnox bring its tab forward; WezTerm does, and so does kitty with remote control on, while Windows Terminal cannot list its tabs";

function failed(reason: string): Shown {
  return { answer: DELIVERY.FAILED, reason };
}

/** The reason a rejection carried, as Tauri hands a Rust error over as its text. */
export function reasonOf(error: unknown, fallback: string): string {
  if (typeof error === 'string' && error !== '') return error;
  if (error instanceof Error && error.message !== '') return error.message;
  return fallback;
}

/**
 * Brings a session's own app forward through that app's own controls: an editor through its command line
 * and the Memnox extension, a terminal by listing its panes, choosing the session's with TabMatch, and
 * focusing it. Where none of that reaches, it answers failed with why, and the caller opens the live window.
 */
export class SessionFocus {
  constructor(private readonly terminals: Terminals) {}

  async focus(host: DisplayHost | undefined): Promise<Shown> {
    if (host === undefined || (host.app === undefined && host.appPath === undefined && host.cwd === undefined && host.tty === undefined)) {
      return failed('where it runs was never noted, so there is no window or folder to bring up');
    }
    if (editorOf(host) !== undefined) return this.terminals.focusEditor(host).catch((error: unknown) => failed(reasonOf(error, 'its editor would not come forward')));
    const named = terminalOf(host);
    if (named === TERMINAL.WINDOWS_TERMINAL) return failed('Windows Terminal cannot list its tabs to another app, so which tab is the session\'s cannot be told');
    const app = host.app ?? host.appPath;
    // Another terminal's tab in the same folder is not this one, so every terminal is asked only when none was noted.
    if (named === undefined && app !== undefined) return failed(`${app} has no command line Memnox can bring a tab forward through; WezTerm, and kitty with remote control on, do`);
    const asked: readonly TerminalKind[] = named === undefined ? LISTING_TERMINALS : [named];
    const reasons: string[] = [];
    for (const terminal of asked) {
      const title = terminalTitle(terminal);
      let panes;
      try {
        panes = await this.terminals.panes(terminal);
      } catch (error) {
        // A terminal not here says nothing worth repeating unless the host named it.
        if (named !== undefined) reasons.push(reasonOf(error, `${title} did not list its tabs`));
        continue;
      }
      const choice = choosePane(panes, host, title);
      if ('why' in choice) {
        reasons.push(choice.why);
        continue;
      }
      try {
        await this.terminals.focusPane(terminal, choice.pane);
        return { answer: DELIVERY.TYPED };
      } catch (error) {
        reasons.push(reasonOf(error, `${title} would not bring its tab forward`));
      }
    }
    return failed(reasons[0] ?? NO_TERMINAL_CONTROL);
  }
}
