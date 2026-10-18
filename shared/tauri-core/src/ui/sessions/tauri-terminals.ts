import { invoke } from '@tauri-apps/api/core';
import { DELIVERY, type DisplayHost } from '@memnox/core/wire';
import { reasonOf, type EditorKind, type Shown, type TerminalKind, type TerminalPane, type Terminals } from '../../core';

/** Rust's `focus` commands, each reaching a tool only through that tool's own documented controls. */
export class TauriTerminals implements Terminals {
  panes(terminal: TerminalKind): Promise<readonly TerminalPane[]> {
    return invoke<TerminalPane[]>('terminal_panes', { terminal });
  }

  async focusPane(terminal: TerminalKind, pane: TerminalPane): Promise<void> {
    await invoke('terminal_focus', { terminal, id: pane.id });
  }

  focusEditor(host: DisplayHost): Promise<Shown> {
    return this.shown(invoke<Shown>('focus_editor', { host }), 'its editor would not come forward');
  }

  launchInTerminal(terminal: TerminalKind | undefined, line: string, folder: string, background: boolean): Promise<Shown> {
    return this.shown(invoke<Shown>('launch_in_terminal', { terminal: terminal ?? null, line, folder, background }), 'no terminal would open a tab');
  }

  launchInEditor(editor: EditorKind, folder: string, request: string): Promise<Shown> {
    return this.shown(invoke<Shown>('launch_in_editor', { editor, folder, request }), 'the editor would not open on the repository');
  }

  openAppLinks(links: readonly string[]): Promise<Shown> {
    return this.shown(invoke<Shown>('open_app_links', { links }), 'its app did not answer its link');
  }

  /** A command that broke on the way still answers failed with a reason, so the voice never waits on it. */
  private shown(asked: Promise<Shown>, fallback: string): Promise<Shown> {
    return asked.catch((error: unknown) => ({ answer: DELIVERY.FAILED, reason: reasonOf(error, fallback) }));
  }
}
