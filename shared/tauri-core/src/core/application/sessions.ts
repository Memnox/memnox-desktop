import { DAEMON_METHOD, type CardExcerpt, type DaemonRequest, type SessionCard, type SessionView } from '@memnox/core/wire';
import { agentKind } from '../domain/agent-colour';
import { isActive } from '../domain/session-status';
import { cardStatus } from '../domain/session-text';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Timer } from './talking';

/** What the island, the side panel and the switcher draw of the sessions, replaced whole on every change. */
export interface SessionsState {
  /** Every recent session, the most recently active first, without Memnox's own operator. */
  readonly cards: readonly SessionCard[];
  /** The session the open island is about; the first card until the person picks another. */
  readonly focusId: string | undefined;
  /** That session read up close, once it has been read. */
  readonly focused: SessionView | undefined;
  /** The open island shows the focused session up close rather than all of them. */
  readonly detail: boolean;
  /** The island is open, so the list is read quickly. */
  readonly opened: boolean;
}

/** Read quickly while the island is open and slowly while it only shows logos, as the Mac reads them. */
export const SESSIONS_REFRESH = { openMs: 2_000, restingMs: 5_000 } as const;

/** Memnox's own operator answers the person; it is not one of the agents being watched. */
const OPERATOR_KIND_PREFIX = 'memnox';

/**
 * The sessions, ported from the Mac's `IslandPanel.refresh` and `Conversation.sessionsList`, `sessionView`
 * and `sessionDiff`: the list read again and again, the focused one read up close while the island is open.
 * It decides nothing; the daemon says what runs, and this keeps what it said for the screens.
 */
export class Sessions {
  private current: SessionsState = { cards: [], focusId: undefined, focused: undefined, detail: false, opened: false };
  private readonly listeners = new Set<() => void>();
  private cancelNext: (() => void) | undefined;
  private running = false;
  /** Each read is numbered, so one that returns after a newer one started never overwrites it. */
  private reading = 0;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly timer: Timer,
  ) {}

  get state(): SessionsState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** The sessions busy right now, which put their logos beside the notch. */
  get working(): SessionCard[] {
    return this.current.cards.filter((card) => isActive(cardStatus(card)));
  }

  /** The card the open island is about. */
  get focusCard(): SessionCard | undefined {
    return this.current.cards.find((card) => card.sessionId === this.current.focusId) ?? this.current.cards[0];
  }

  /** Starts reading, and keeps reading until `stop`. */
  start(): void {
    if (this.running) return;
    this.running = true;
    void this.refresh();
  }

  stop(): void {
    this.running = false;
    this.cancelNext?.();
    this.cancelNext = undefined;
  }

  /** The island opened or closed: the cadence changes, and closing turns it back to all the sessions. */
  opened(on: boolean): void {
    if (on === this.current.opened) return;
    this.update(on ? { opened: true, detail: false } : { opened: false, detail: false });
    if (this.running) void this.refresh();
  }

  /** The open island turned to one session up close, or back to all of them. */
  showDetail(on: boolean): void {
    this.update({ detail: on });
  }

  /** A row was hovered or clicked: that session comes into focus and is read at once. */
  focus(sessionId: string): void {
    if (this.current.focusId === sessionId) return;
    this.update({ focusId: sessionId, focused: undefined });
    if (this.running) void this.refresh();
  }

  /** One read of the list, and of the focused session while the island is open, then the next one timed. */
  async refresh(): Promise<void> {
    this.cancelNext?.();
    this.cancelNext = undefined;
    const reading = ++this.reading;
    const cards = (await this.list()).filter((card) => !agentKind(card.agent).startsWith(OPERATOR_KIND_PREFIX));
    if (reading !== this.reading) return;
    const changes: { -readonly [K in keyof SessionsState]?: SessionsState[K] } = {};
    if (JSON.stringify(cards) !== JSON.stringify(this.current.cards)) changes.cards = cards;
    const focusId = cards.some((card) => card.sessionId === this.current.focusId) ? this.current.focusId : cards[0]?.sessionId;
    if (focusId !== this.current.focusId) Object.assign(changes, { focusId, focused: undefined });
    this.update(changes);
    if (this.current.opened && focusId !== undefined) {
      const view = await this.view(focusId);
      if (reading !== this.reading) return;
      if (JSON.stringify(view) !== JSON.stringify(this.current.focused)) this.update({ focused: view });
    }
    if (this.running) this.cancelNext = this.timer(this.current.opened ? SESSIONS_REFRESH.openMs : SESSIONS_REFRESH.restingMs, () => void this.refresh());
  }

  /** The sessions lately, most recently active first; none when the daemon is away. */
  async list(): Promise<SessionCard[]> {
    try {
      return (await requestOnce(this.link, this.request(DAEMON_METHOD.SESSIONS_LIST))).sessions ?? [];
    } catch {
      return [];
    }
  }

  /** A session as it is right now; undefined when the daemon does not know it. */
  async view(sessionId: string): Promise<SessionView | undefined> {
    try {
      return (await requestOnce(this.link, { ...this.request(DAEMON_METHOD.SESSION_VIEW), sessionId })).session;
    } catch {
      return undefined;
    }
  }

  /** One file's diff as the session left it, for the live window to open under the file's name. */
  async diff(sessionId: string, path: string): Promise<CardExcerpt | undefined> {
    try {
      return (await requestOnce(this.link, { ...this.request(DAEMON_METHOD.SESSION_VIEW), sessionId, path })).diff;
    } catch {
      return undefined;
    }
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    return { id: this.ids.next(), method };
  }

  private update(changes: Partial<SessionsState>): void {
    if (Object.keys(changes).length === 0) return;
    this.current = { ...this.current, ...changes };
    for (const listener of this.listeners) listener();
  }
}
