import type { DaemonEvent } from '@memnox/core/wire';
import { cueForAnswer, cueForEvent, cueForProposal, type Cue, type PressEnd } from '../domain/chimes';
import { quietHere } from '../domain/quiet';
import type { Chimes } from './ports/chimes';

/**
 * When a chime plays, ported from where the Mac's `Conversation` calls `chimes.play`: a call that
 * starts waiting, one settled elsewhere, and every answer given by hand. Turned off, it plays nothing.
 */
export class Chiming {
  private on = true;

  constructor(
    private readonly chimes: Chimes,
    private readonly phoneHolds: () => boolean = () => false,
  ) {}

  /** On unless the person turns it off. */
  set enabled(on: boolean) {
    this.on = on;
  }

  get enabled(): boolean {
    return this.on;
  }

  heard(event: DaemonEvent): Cue | undefined {
    return this.play(cueForEvent(event, quietHere(event, this.phoneHolds())));
  }

  answered(answer: string, end: PressEnd): Cue | undefined {
    return this.play(cueForAnswer(answer, end));
  }

  proposalAnswered(sent: boolean, end: PressEnd): Cue | undefined {
    return this.play(cueForProposal(sent, end));
  }

  private play(cue: Cue | undefined): Cue | undefined {
    if (cue === undefined || !this.on) return undefined;
    this.chimes.play(cue);
    return cue;
  }
}
