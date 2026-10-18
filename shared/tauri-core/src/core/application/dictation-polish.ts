import { DAEMON_METHOD, type DaemonRequest } from '@memnox/core/wire';
import type { DictationFamily } from '../domain/dictation-text';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Timer } from './talking';

/** Long enough for a warm Claude Code on its quick model, short enough that the cursor never seems stuck. */
export const POLISH_PATIENCE_MS = 3_500;
/** Editing a selection has nothing to fall back on, so it waits a little longer for its one answer. */
export const EDIT_PATIENCE_MS = 12_000;

/**
 * Asks the daemon to have dictation polished by the person's own Claude Code, and stops waiting once it
 * took longer than a person waits for a paste. Undefined means this computer's own cleanup is typed
 * instead, so nothing is lost to a slow or absent answer. No model is called from here. Ported from
 * the Mac's `DictationPolish`.
 */
export class DictationPolish {
  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly timer: Timer,
  ) {}

  /** Starts the process ahead of the words, as the key goes down; nothing waits on it. */
  warm(): void {
    void requestOnce(this.link, { id: this.ids.next(), method: DAEMON_METHOD.POLISH_WARM }).catch(() => undefined);
  }

  polish(said: string, family: DictationFamily, vocabulary: readonly string[], selection?: string, patienceMs = POLISH_PATIENCE_MS): Promise<string | undefined> {
    const request: DaemonRequest = { id: this.ids.next(), method: DAEMON_METHOD.POLISH, said, family, vocabulary: [...vocabulary] };
    if (selection !== undefined) request.selection = selection;
    const answer = requestOnce(this.link, request).then(
      (response) => (response.ok ? response.polished?.trim() || undefined : undefined),
      () => undefined,
    );
    let cancel: () => void = () => undefined;
    const late = new Promise<undefined>((resolve) => {
      cancel = this.timer(patienceMs, () => resolve(undefined));
    });
    return Promise.race([answer, late]).finally(cancel);
  }
}
