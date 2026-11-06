import { invoke } from '@tauri-apps/api/core';
import { DELIVERY, type DisplayHost } from '@memnox/core/wire';
import { reasonOf, type EditorKind, type Shown, type TerminalKind, type TerminalPane, type Terminals } from '../../core';
import type { AgentHomeKind } from '../../core/domain/agent-homes';
import { TAURI_COMMAND } from '../adapters/tauri-commands';

/** Rust's `focus` commands, each reaching a tool only through that tool's own documented controls. */
export class TauriTerminals implements Terminals {
  panes(terminal: TerminalKind): Promise<readonly TerminalPane[]> {
    return invoke<TerminalPane[]>(TAURI_COMMAND.terminalPanes, { terminal });
  }

  async focusPane(terminal: TerminalKind, pane: TerminalPane): Promise<void> {
    await invoke(TAURI_COMMAND.terminalFocus, { terminal, id: pane.id });
  }

  focusEditor(host: DisplayHost): Promise<Shown> {
    return this.shown(invoke<Shown>(TAURI_COMMAND.focusEditor, { host }), 'its editor would not come forward');
  }

  launchInTerminal(terminal: TerminalKind | undefined, line: string, folder: string, background: boolean): Promise<Shown> {
    return this.shown(invoke<Shown>(TAURI_COMMAND.launchInTerminal, { terminal: terminal ?? null, line, folder, background }), 'no terminal would open a tab');
  }

  launchInHome(home: AgentHomeKind, line: string, folder: string): Promise<Shown> {
    return this.shown(invoke<Shown>(TAURI_COMMAND.launchInHome, { home, line, folder }), 'the app would not open a window');
  }

  launchInEditor(editor: EditorKind, folder: string, request: string): Promise<Shown> {
    return this.shown(invoke<Shown>(TAURI_COMMAND.launchInEditor, { editor, folder, request }), 'the editor would not open on the repository');
  }

  openAppLinks(links: readonly string[]): Promise<Shown> {
    return this.shown(invoke<Shown>(TAURI_COMMAND.openAppLinks, { links }), 'its app did not answer its link');
  }

  /** A command that broke on the way still answers failed with a reason, so the voice never waits on it. */
  private shown(asked: Promise<Shown>, fallback: string): Promise<Shown> {
    return asked.catch((error: unknown) => ({ answer: DELIVERY.FAILED, reason: reasonOf(error, fallback) }));
  }
}
