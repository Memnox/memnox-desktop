import { ask, end, NO_HISTORY, parseHistory, replied, type History } from '../domain/history';
import type { TalkState } from './talking';

/** Where the history is kept between launches: a file on the Mac, the webview's own storage here. */
export interface HistoryStore {
  load(): string | null;
  save(text: string): void;
}

/** The voice's turns as the keeper reads them, so it follows any talking without depending on how it talks. */
export interface TurnSource {
  readonly state: TalkState;
  observe(listener: () => void): () => void;
}

/**
 * Keeps every question asked and its answer, ported from the Mac's `IslandPanel.keepHistory` and the
 * places `Conversation` writes to it: a turn starts when words are heard, grows as the reply streams, and
 * ends when the voice goes quiet, kept with why when it failed so it can be asked again.
 */
export class HistoryKeeper {
  private current: History;
  private readonly listeners = new Set<() => void>();
  private last: TalkState | undefined;

  constructor(
    private readonly store: HistoryStore,
    /** A fresh id per exchange; the core has no randomness of its own, so the window gives one. */
    private readonly newId: () => string,
    private readonly now: () => number = Date.now,
  ) {
    this.current = parseHistory(store.load());
  }

  get history(): History {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Follows the voice from now on; returns what stops it. */
  follow(turns: TurnSource): () => void {
    this.last = turns.state;
    return turns.observe(() => this.turned(turns.state));
  }

  /** Read again from the store, as a second window does when the first one wrote. */
  reload(): void {
    this.current = parseHistory(this.store.load());
    this.changed(false);
  }

  forget(): void {
    this.current = NO_HISTORY;
    this.changed(true);
  }

  /** One change of the voice's state, compared with the one before. */
  turned(state: TalkState): void {
    const before = this.last;
    this.last = state;
    let next = this.current;
    // New words heard and sent: a new exchange, which ends any left open.
    if (state.phase === 'thinking' && state.heard !== undefined && (before?.phase !== 'thinking' || before.heard !== state.heard)) {
      next = ask(next, state.heard, this.now(), this.newId());
    }
    if (state.reply !== '' && state.reply !== before?.reply) next = replied(next, state.reply);
    if (state.phase === 'idle' && before !== undefined && before.phase !== 'idle') next = end(next, this.now(), state.failure);
    if (next === this.current) return;
    this.current = next;
    this.changed(true);
  }

  private changed(save: boolean): void {
    if (save) this.store.save(JSON.stringify(this.current));
    for (const listener of this.listeners) listener();
  }
}
