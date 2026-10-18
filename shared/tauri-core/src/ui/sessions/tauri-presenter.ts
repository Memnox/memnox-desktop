import { invoke } from '@tauri-apps/api/core';
import { emit } from '@tauri-apps/api/event';
import type { TraceCard } from '@memnox/core/wire';
import type { Presenter, SummaryCard, WalkCard } from '../../core';

/** Told to the floating cards' window, which draws a summary, a walk or a trace in the top left. */
export const FLOATING_CARD_EVENT = 'floating-card';
/** Told to every window that draws a card, so the daemon's dismiss takes them all down. */
export const DISMISS_EVENT = 'dismiss-cards';
/** Told to the island when the side panel asks a question again. */
export const ASK_AGAIN_EVENT = 'ask-again';

/**
 * The daemon's SHOW displays on Windows and Linux: the session windows are this app's own webview windows,
 * made in Rust, and the floating cards are told to whichever window draws them.
 */
export class TauriPresenter implements Presenter {
  async live(sessionId: string): Promise<void> {
    await invoke('open_live_session', { sessionId }).catch(() => undefined);
  }

  async turnTo(sessionId: string): Promise<void> {
    await invoke('open_switcher', { sessionId }).catch(() => undefined);
  }

  async card(card: SummaryCard): Promise<void> {
    await emit(FLOATING_CARD_EVENT, { kind: 'summary', ...card });
  }

  async walk(walk: WalkCard): Promise<void> {
    await emit(FLOATING_CARD_EVENT, { kind: 'walk', ...walk });
  }

  async trace(trace: TraceCard, title: string): Promise<void> {
    await emit(FLOATING_CARD_EVENT, { kind: 'trace', title, trace });
  }

  async board(title: string): Promise<void> {
    await invoke('open_board', { title }).catch(() => undefined);
  }

  async dismissAll(): Promise<void> {
    await emit(DISMISS_EVENT);
    await invoke('dismiss_session_windows').catch(() => undefined);
  }

  openFolder(path: string): Promise<boolean> {
    return invoke<void>('open_folder', { path }).then(
      () => true,
      () => false,
    );
  }

  openLink(url: string): Promise<boolean> {
    return invoke<void>('open_link', { url }).then(
      () => true,
      () => false,
    );
  }
}
