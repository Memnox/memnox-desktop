import type { WorkspaceHeldCall } from '../domain/workspace-wire';
import type { Timer } from './talking';
import type { WorkspaceAnswering } from './workspace-answering';

/** Often enough that a teammate is not kept waiting, rarely enough to stay quiet on the network. */
export const INBOX_EVERY_MS = 20_000;
/** How often the clock is looked at for a gap that says the computer slept. */
const WAKE_TICK_MS = 5_000;
/** A tick this late means the computer was asleep, since a webview's timers stop while it sleeps. */
const SLEPT_AFTER_MS = 30_000;

/** What a read of the inbox does to the rest of the app. */
export interface TeamInboxHandlers {
  /** A teammate's call started waiting on the person. */
  arrived(call: WorkspaceHeldCall): void;
  /** One stopped waiting, with who answered where the workspace said, and no note at all for a sign out. */
  gone(id: string, note: string | undefined): void;
  /** The workspace revoked the credential, so it is forgotten here rather than sent again every poll. */
  signedOut(): void;
}

/**
 * Reads the team's inbox now, then every 20 seconds, and at once when the computer wakes from sleep, since asleep
 * nothing was read. The wake is seen as a jump in the clock between two ticks, which holds the same on Windows and
 * Linux without asking the system. Ported from the Mac's `readInbox` and its wake observer.
 */
export class TeamInbox {
  private next: (() => void) | undefined;
  private tick: (() => void) | undefined;
  private reading = false;
  private lastTick = 0;

  constructor(
    private readonly answering: WorkspaceAnswering,
    private readonly handlers: TeamInboxHandlers,
    private readonly timer: Timer,
    private readonly now: () => number = Date.now,
  ) {}

  start(): void {
    this.lastTick = this.now();
    this.watchForWake();
    void this.read();
  }

  /** Reads now and starts the interval over, as after a sign in. */
  read(): Promise<void> {
    this.next?.();
    return this.poll();
  }

  stop(): void {
    this.next?.();
    this.tick?.();
  }

  private async poll(): Promise<void> {
    if (!this.reading) {
      this.reading = true;
      try {
        const change = await this.answering.refresh();
        if (change.signedOut) this.handlers.signedOut();
        for (const id of change.gone) this.handlers.gone(id, change.signedOut ? undefined : change.answeredElsewhere.get(id));
        for (const call of change.arrived) this.handlers.arrived(call);
      } finally {
        this.reading = false;
      }
    }
    this.next = this.timer(INBOX_EVERY_MS, () => void this.poll());
  }

  private watchForWake(): void {
    this.tick = this.timer(WAKE_TICK_MS, () => {
      const at = this.now();
      const slept = at - this.lastTick > SLEPT_AFTER_MS;
      this.lastTick = at;
      if (slept) void this.read();
      this.watchForWake();
    });
  }
}
