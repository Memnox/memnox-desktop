import type { Speaker } from './ports/speaker';
import type { VoicePreferences } from './voice-preferences';

/** The voice held quiet while somebody may be talking over it, then let carry on. */
export interface Hushable {
  hush(): void;
  carryOn(): void;
}

/** Long enough for the longest sentence it says to finish playing and come back through the microphone. */
export const ECHO_LINGERS_MS = 15_000;
/** Kept a little longer than any look back asks for, so the list never grows for ever. */
const KEPT_FOR_MS = 60_000;

/**
 * The voice as everything else hears it, ported from what the Mac's `Voice` keeps: what it said lately,
 * so its echo is told from the person, whether it is speaking now, and the mute, which drops every
 * sentence while the words still show. Hush and carry on pass through to the platform's player.
 */
export class Mouth implements Speaker, Hushable {
  private said: { sentence: string; at: number }[] = [];
  private playing = 0;
  private hushed = false;

  constructor(
    private readonly inner: Speaker & Partial<Hushable>,
    private readonly preferences: VoicePreferences,
    private readonly now: () => number = Date.now,
  ) {
    // A mute that waits for the end of the sentence is no mute, so the voice stops the moment it is turned on.
    preferences.observe(() => {
      if (preferences.choices.muted) inner.stop();
    });
  }

  /** Whether a sentence is queued or playing, which is when its echo can be in the room. */
  get speaking(): boolean {
    return this.playing > 0 && !this.hushed;
  }

  queue(sentence: string): void {
    if (this.preferences.choices.muted) return;
    const at = this.now();
    this.said = [...this.said.filter((each) => at - each.at < KEPT_FOR_MS), { sentence, at }];
    this.playing += 1;
    this.inner.queue(sentence);
    void this.inner.drained().then(() => {
      this.playing = Math.max(0, this.playing - 1);
    });
  }

  drained(): Promise<void> {
    return this.inner.drained();
  }

  stop(): void {
    this.hushed = false;
    this.inner.stop();
  }

  hush(): void {
    this.hushed = true;
    this.inner.hush?.();
  }

  carryOn(): void {
    this.hushed = false;
    this.inner.carryOn?.();
  }

  /** Everything it said in the last `ms`, as one text, for telling its own words from the person's. */
  spoken(ms = ECHO_LINGERS_MS): string {
    const from = this.now() - ms;
    return this.said
      .filter((each) => each.at >= from)
      .map((each) => each.sentence)
      .join(' ');
  }
}
