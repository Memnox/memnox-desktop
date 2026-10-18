/**
 * How loud the voice in or out is right now, from nothing to one on a decibel scale, read by the orb
 * and the waveform every frame. The microphone writes it while listening; the speaker can write it while
 * speaking once Rust reports its output level, which is the seam the voice work picks up.
 */
export class Loudness {
  private level = 0;

  get value(): number {
    return this.level;
  }

  set(level: number): void {
    this.level = Math.min(1, Math.max(0, level));
  }
}

/** The one the island draws from. */
export const loudness = new Loudness();
