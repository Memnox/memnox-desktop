import { invoke } from '@tauri-apps/api/core';
import { emit, listen } from '@tauri-apps/api/event';
import type { DisplayHost, TraceCard } from '@memnox/core/wire';
import type { Presenter, Shown, SummaryCard, WalkCard } from '../../core';
import { openSession, SESSION_TURNED_EVENT } from './open-session';

/** Told to the floating cards' window, which draws a summary, a walk or a trace in the top left. */
export const FLOATING_CARD_EVENT = 'floating-card';
/** Told to every window that draws a card, so the daemon's dismiss takes them all down. */
export const DISMISS_EVENT = 'dismiss-cards';
/** Told to the island when the side panel asks a question again. */
export const ASK_AGAIN_EVENT = 'ask-again';
/** Longer than the switcher's turn through every session, after which the session is opened anyway. */
const SWITCHER_WAIT_MS = 6_000;

/**
 * The daemon's SHOW displays on Windows and Linux: the session windows are this app's own webview windows,
 * made in Rust, and the floating cards are told to whichever window draws them.
 */
export class TauriPresenter implements Presenter {
  async live(sessionId: string): Promise<void> {
    await invoke('open_live_session', { sessionId }).catch(() => undefined);
  }

  /**
   * The Mac's order: the switcher turns through the sessions to this one, then its own tab or editor comes
   * forward through that tool's own controls, or its live window when that cannot be done.
   */
  async focus(sessionId: string, host: DisplayHost | undefined): Promise<Shown> {
    let finished: () => void = () => undefined;
    const turned = new Promise<void>((resolve) => (finished = resolve));
    const stop = await listen<string>(SESSION_TURNED_EVENT, (event) => event.payload === sessionId && finished());
    const wait = setTimeout(finished, SWITCHER_WAIT_MS);
    try {
      // No switcher is no reason not to open it, so a refusal goes straight on.
      await invoke('open_switcher', { sessionId }).then(
        () => turned,
        () => undefined,
      );
    } finally {
      clearTimeout(wait);
      stop();
    }
    return openSession(sessionId, host);
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
