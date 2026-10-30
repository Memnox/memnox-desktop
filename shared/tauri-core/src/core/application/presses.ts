import { PROPOSING_METHODS, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import type { DaemonLink } from './ports/daemon-link';

/**
 * One press in the Memnox window as the island hears of it: `raised` is absent while the daemon has not answered,
 * and names the proposals its answer made once it has. An id only ever comes from the answer to a request the
 * window sent, never from an event or a flag on the socket, which any process on this computer can reach.
 */
export interface Press {
  readonly token: string;
  readonly raised?: readonly string[];
}

/** How the window tells the island of a press: a Rust command only the window's own labels may call. */
export type PressChannel = (press: Press) => void;

/** Every proposal an answer names, wherever the method puts them. */
export function proposalIds(response: DaemonResponse): string[] {
  return [
    ...(response.proposed === undefined ? [] : [response.proposed]),
    ...(response.packProposed ?? []),
    ...(response.profileApplied?.proposed ?? []),
    ...(response.indexInstalled?.proposed ?? []),
  ];
}

/**
 * The daemon as the Memnox window reaches it, telling the island of every press of a method that can propose and of
 * the proposals any answer made, so one shared link covers every page rather than each use case remembering to. The
 * island's own link stays plain.
 */
export class PressingLink implements DaemonLink {
  constructor(
    private readonly link: DaemonLink,
    private readonly told: PressChannel,
    /** A fresh token per press, from the adapter, since the core reaches no platform of its own. */
    private readonly token: () => string,
  ) {}

  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    const token = this.token();
    // Only a method that can raise a proposal is a press, so a background read never makes an unasked one wait.
    const pressing = PROPOSING_METHODS.includes(request.method);
    if (pressing) this.told({ token });
    let answered = false;
    try {
      for await (const response of this.link.stream(request)) {
        // Told before the page sees it, so the page and the island never disagree on what was pressed for.
        const raised = proposalIds(response);
        if (!answered) {
          answered = true;
          if (pressing || raised.length > 0) this.told({ token, raised });
        } else if (raised.length > 0) this.told({ token, raised });
        yield response;
      }
    } finally {
      if (!answered && pressing) this.told({ token, raised: [] });
    }
  }
}

/** Long enough for the proposal's event to be handled behind what is being said, short enough to leave nothing open. */
export const PRESS_LIFETIME_MS = 60_000;
/** A page raises a handful at once at most, so the oldest is dropped long before this fills. */
export const MOST_PRESSES = 32;
/** A proposal waits this long for the press naming it, since its event can reach the island before the answer does. */
export const PRESS_GRACE_MS = 2_000;
/** And this long at most while a press is still unanswered, since launching with a profile answers once the terminal is up. */
export const LONGEST_PRESS_MS = 10_000;
const PRESS_STEP_MS = 25;


/** The island's side: the proposals the window pressed for, each taken once and only while it is fresh. */
export class Presses {
  private readonly named = new Map<string, number>();
  /** Presses not answered yet, by when they began; one whose window closed mid press goes after the longest wait. */
  private readonly inFlight = new Map<string, number>();
  /** Presses already answered, since two calls over the bridge can land out of order and a late start must not linger. */
  private readonly answered = new Map<string, number>();

  constructor(
    private readonly sleep: (ms: number) => Promise<void>,
    private readonly now: () => number = Date.now,
  ) {}

  heard(press: Press): void {
    if (press.raised === undefined) {
      if (!this.answered.has(press.token)) this.inFlight.set(press.token, this.now());
      return;
    }
    const at = this.now();
    this.prune(at);
    this.inFlight.delete(press.token);
    this.answered.set(press.token, at);
    for (const id of press.raised) {
      this.named.delete(id);
      this.named.set(id, at);
    }
    // Bounded, so a page pressed over and over cannot grow it; a Map keeps insertion order, so the first is the oldest.
    for (const oldest of this.named.keys()) {
      if (this.named.size <= MOST_PRESSES) break;
      this.named.delete(oldest);
    }
  }

  /** Whether a press raised this proposal, waiting the grace, and longer while a press is still unanswered. */
  async take(id: string): Promise<boolean> {
    const began = this.now();
    while (true) {
      if (this.takeNow(id)) return true;
      const waited = this.now() - began;
      if (waited >= LONGEST_PRESS_MS) return false;
      if (waited >= PRESS_GRACE_MS && this.inFlight.size === 0) return false;
      await this.sleep(PRESS_STEP_MS);
    }
  }

  private takeNow(id: string): boolean {
    this.prune(this.now());
    return this.named.delete(id);
  }

  private prune(at: number): void {
    for (const [id, when] of this.named) if (at - when >= PRESS_LIFETIME_MS) this.named.delete(id);
    for (const [token, when] of this.inFlight) if (at - when >= LONGEST_PRESS_MS) this.inFlight.delete(token);
    for (const [token, when] of this.answered) if (at - when >= LONGEST_PRESS_MS) this.answered.delete(token);
  }
}
