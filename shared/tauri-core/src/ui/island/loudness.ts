/**
 * How loud the voice in or out is right now, from nothing to one on a decibel scale, read by the orb
 * and the waveform every frame. The microphone writes it while listening and Kokoro while it speaks,
 * and the louder of the two is what moves the orb, as the Mac's `max(audio.micLevel, voice.level)` does.
 */
export class Loudness {
  private heard = 0;
  private playing = 0;

  get value(): number {
    return Math.max(this.heard, this.playing);
  }

  /** The microphone's level. */
  set(level: number): void {
    this.heard = clamped(level);
  }

  /** The voice's own level as it plays, which sends the orb's syllable rings from chin to crown. */
  voice(level: number): void {
    this.playing = clamped(level);
  }
}

function clamped(level: number): number {
  return Number.isFinite(level) ? Math.min(1, Math.max(0, level)) : 0;
}

/** The one the island draws from. */
export const loudness = new Loudness();
