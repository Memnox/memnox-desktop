import { endOfSpeechPause, joinedSpeech } from '../domain/turn-taking';
import type { Ear, EarEvent } from './ports/ear';
import type { Timer } from './talking';

/** The pause after which the ear itself ends a stretch of speech; the rest of the wait is the core's to add. */
export const EAR_END_OF_SPEECH_MS = 800;
/** The longest one listen may run once somebody started, so a room that never goes quiet still ends. */
const LONGEST_LISTEN_MS = 45_000;
/** How long a close may take before it is given up on, since the window may already be going. */
const CLOSE_WAIT_MS = 3_000;

/** What one listen heard: their words, nothing, or why the microphone could not be used. */
export type Heard = { readonly kind: 'words'; readonly words: string } | { readonly kind: 'nothing' } | { readonly kind: 'failed'; readonly why: string };

export interface HearOptions {
  /** How long to wait for a first word before giving up; ignored while a key is held. */
  readonly waitMs: number;
  /** Held keys: listen until they come up, then this much longer so the last syllable is not cut off. */
  readonly holding?: { readonly released: Promise<void>; readonly tailMs: number };
  /** Words as they come, so the island shows them as they are said. */
  readonly onWords?: (soFar: string) => void;
  readonly onLevel?: (level: number) => void;
  /** Called the moment the person starts talking. */
  readonly onSpeech?: () => void;
  /** Ends the listen early, with whatever was heard, as a tap on the island does. */
  readonly cut?: Promise<void>;
}

/**
 * One turn of listening on the open ear: until they pause long enough for what they said, or for as long
 * as a key is held. A pause that sounds like somebody still thinking is waited out, so one question said
 * in two breaths arrives as one.
 */
export function hear(ear: Ear, timer: Timer, options: HearOptions): Promise<Heard> {
  return new Promise<Heard>((resolve) => {
    let finals = '';
    let partial = '';
    let started = false;
    let closing = false;
    let settled = false;
    let failure: string | undefined;
    const cancels: (() => void)[] = [];
    let endWait: (() => void) | undefined;

    const settle = (heard: Heard) => {
      if (settled) return;
      settled = true;
      for (const cancel of cancels) cancel();
      endWait?.();
      resolve(heard);
    };
    const result = (): Heard => {
      if (failure !== undefined) return { kind: 'failed', why: failure };
      const words = joinedSpeech(finals, partial).trim();
      return words === '' ? { kind: 'nothing' } : { kind: 'words', words };
    };
    // The ear finishes the stretch under way as it closes, so its last words arrive before `closed`.
    const finish = () => {
      if (closing) return;
      closing = true;
      cancels.push(timer(CLOSE_WAIT_MS, () => settle(result())));
      void ear.close().catch(() => settle(result()));
    };

    const onEvent = (event: EarEvent) => {
      if (settled) return;
      switch (event.kind) {
        case 'level':
          options.onLevel?.(event.heard);
          return;
        case 'speech':
          if (!started) options.onSpeech?.();
          started = true;
          // They carried on, so the end of what they were saying has not come yet.
          endWait?.();
          endWait = undefined;
          return;
        case 'words':
          if (event.final) {
            finals = joinedSpeech(finals, event.text);
            partial = '';
          } else {
            partial = event.text;
          }
          started = true;
          options.onWords?.(joinedSpeech(finals, partial));
          if (event.final && options.holding === undefined && !closing) {
            endWait?.();
            endWait = timer(Math.max(0, endOfSpeechPause(finals) - EAR_END_OF_SPEECH_MS), finish);
          }
          return;
        case 'closed':
          if (event.error !== undefined && event.error !== null && finals === '' && partial === '') failure = event.error;
          settle(result());
          return;
      }
    };

    ear.open(onEvent, { partials: options.onWords !== undefined }).then(
      () => {
        if (settled) return;
        if (options.holding !== undefined) {
          const { tailMs } = options.holding;
          void options.holding.released.then(() => cancels.push(timer(tailMs, finish)));
        } else if (options.waitMs > 0) {
          cancels.push(
            timer(options.waitMs, () => {
              if (!started) finish();
            }),
          );
        }
        cancels.push(timer(LONGEST_LISTEN_MS, finish));
        void options.cut?.then(finish);
      },
      (error: unknown) => settle({ kind: 'failed', why: error instanceof Error ? error.message : String(error) }),
    );
  });
}
