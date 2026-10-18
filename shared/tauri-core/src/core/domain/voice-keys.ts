/**
 * The keys held down to dictate and to say a rule, read from what the platform reports of the keyboard.
 * Ported from the Mac's `DictationKey.swift` and `HoldKeys.swift`, with right Alt standing in for right
 * Option and left Alt for Option, so AltGr typing a character on an international layout never starts one.
 */

/** What the platform reports: the modifiers as they stand, or a key that is not one going down. */
export type KeyReport =
  | { readonly kind: 'modifiers'; readonly ctrl: boolean; readonly leftAlt: boolean; readonly rightAlt: boolean; readonly shift: boolean; readonly meta: boolean }
  | { readonly kind: 'key' };

/** Calls `fire` after `ms` unless the returned function is called first. */
export type KeyTimer = (ms: number, fire: () => void) => () => void;

export const VOICE_KEY_TIMING = {
  /** Long enough that right Alt pressed for a character never starts dictating. */
  dictationMeantAfterMs: 250,
  /** Two taps closer than this are one double tap, which dictates hands free. */
  doubleTapMs: 400,
  /** Long enough that Control Alt with a letter, a common shortcut, never opens a rule by accident. */
  ruleMeantAfterMs: 300,
} as const;

/**
 * Right Alt from anywhere: held, everything said until it is let go is dictated where the cursor is;
 * tapped twice, dictation runs hands free until it is pressed again. A hold only counts once it lasted.
 */
export class DictationKey {
  /** Called once dictation should start, held or hands free. */
  began: () => void = () => undefined;
  /** Called once it should end, let go or pressed again. */
  ended: () => void = () => undefined;
  enabled = true;
  private down = false;
  private pending: (() => void) | undefined;
  private tappedAt: number | undefined;
  private on = false;
  private handsFree = false;

  constructor(
    private readonly timer: KeyTimer,
    private readonly now: () => number = Date.now,
  ) {}

  /** Held, or locked on by a double tap, until let go or pressed again. */
  get active(): boolean {
    return this.on;
  }

  get isHandsFree(): boolean {
    return this.on && this.handsFree;
  }

  saw(report: KeyReport): void {
    if (report.kind === 'key') {
      // A character typed with it is AltGr at work, so a hold not yet begun is called off.
      this.cancelPending();
      this.tappedAt = undefined;
      return;
    }
    if (report.rightAlt && !this.down) {
      this.down = true;
      this.pressedDown(!report.ctrl && !report.shift && !report.meta && !report.leftAlt);
    } else if (!report.rightAlt && this.down) {
      this.down = false;
      this.letGo();
    }
  }

  /** Ends dictation, held or hands free, as letting go does. */
  stop(): void {
    const was = this.on;
    this.on = false;
    this.handsFree = false;
    if (was) this.ended();
  }

  private pressedDown(alone: boolean): void {
    // Hands free ends on the next press, which is how the person says they are done.
    if (this.on && this.handsFree) {
      this.stop();
      return;
    }
    if (!alone || !this.enabled) return;
    if (this.tappedAt !== undefined && this.now() - this.tappedAt < VOICE_KEY_TIMING.doubleTapMs) {
      this.tappedAt = undefined;
      this.handsFree = true;
      this.activate();
      return;
    }
    this.pending = this.timer(VOICE_KEY_TIMING.dictationMeantAfterMs, () => {
      this.pending = undefined;
      this.handsFree = false;
      this.activate();
    });
  }

  private letGo(): void {
    if (this.pending !== undefined) {
      // Up before it counted as a hold: a tap, which a second tap soon after makes hands free.
      this.cancelPending();
      this.tappedAt = this.now();
      return;
    }
    if (this.on && !this.handsFree) this.stop();
  }

  private activate(): void {
    this.on = true;
    this.began();
  }

  private cancelPending(): void {
    this.pending?.();
    this.pending = undefined;
  }
}

/**
 * Control and left Alt held together from anywhere, and nothing else with them: the way into saying a
 * rule. A press let go at once is somebody reaching for another shortcut, so it only counts once it lasted.
 */
export class HoldKeys {
  began: () => void = () => undefined;
  ended: () => void = () => undefined;
  private pending: (() => void) | undefined;
  private on = false;

  constructor(private readonly timer: KeyTimer) {}

  get holding(): boolean {
    return this.on;
  }

  saw(report: KeyReport): void {
    // A letter pressed with the chord is a shortcut, so the hold is called off before it begins.
    if (report.kind === 'key') {
      if (!this.on) this.cancelPending();
      return;
    }
    const pressed = report.ctrl && report.leftAlt && !report.rightAlt && !report.shift && !report.meta;
    if (pressed && !this.on && this.pending === undefined) {
      this.pending = this.timer(VOICE_KEY_TIMING.ruleMeantAfterMs, () => {
        this.pending = undefined;
        this.on = true;
        this.began();
      });
    } else if (!pressed) {
      this.cancelPending();
      if (this.on) {
        this.on = false;
        this.ended();
      }
    }
  }

  private cancelPending(): void {
    this.pending?.();
    this.pending = undefined;
  }
}
