import { HeldNotices, NOTICES_ASKED_KEY, NOTICES_KEY, type HeldNotice } from '../domain/held-notices';
import type { HeldState } from './held-calls';
import type { PreferenceStore } from './ports/preference-store';

/** The system's notifications: whether they may show, asking once, and posting one. */
export interface NoticeSystem {
  granted(): Promise<boolean>;
  ask(): Promise<boolean>;
  post(notice: HeldNotice): void;
}

/**
 * Posts a system notification for each held call the island is not already showing, unless the person turned them
 * off. The system is asked for permission the first time one is due, never at launch, and never asked twice.
 */
export class HeldCallNotices {
  private readonly notices = new HeldNotices();

  constructor(
    private readonly system: NoticeSystem,
    private readonly store: PreferenceStore,
    /** Whether the island is on screen, so the call it shows is already in front of the person. */
    private readonly islandShowing: () => boolean,
  ) {}

  /** Called on every change of what waits; resolves once anything due was posted. */
  async changed(state: HeldState): Promise<void> {
    const waiting = state.waiting.entries.map(({ subject, card }) => ({ subject, label: card.label, what: card.what }));
    const shown = this.islandShowing() ? state.waiting.shown?.subject : undefined;
    // Every change is taken in, also while they are off, so turning them on does not say old calls at once.
    const due = this.notices.next(waiting, shown);
    if (due.length === 0 || this.store.load(NOTICES_KEY) === 'false') return;
    if (!(await this.allowed())) return;
    for (const notice of due) this.system.post(notice);
  }

  private async allowed(): Promise<boolean> {
    if (await this.system.granted()) return true;
    if (this.store.load(NOTICES_ASKED_KEY) === 'true') return false;
    this.store.save(NOTICES_ASKED_KEY, 'true');
    return this.system.ask();
  }
}
