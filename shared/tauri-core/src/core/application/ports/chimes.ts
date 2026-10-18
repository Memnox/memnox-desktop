import type { Cue } from '../../domain/chimes';

/** Plays a cue; the platform decides the sound and whether the person turned them off. */
export interface Chimes {
  play(cue: Cue): void;
}
