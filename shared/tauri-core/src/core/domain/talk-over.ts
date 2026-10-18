/**
 * Telling the person starting to talk from the voice's own sound coming back through the microphone,
 * by loudness alone, so the voice goes quiet on their first syllable rather than on their second word.
 * Levels are on the nothing to one decibel scale the microphone is read on. Ported from `TalkOver.swift`.
 */
export const TALK_OVER = {
  /** How far over its own echo the room has to get, about four decibels, so a loud syllable of its own does not count. */
  margin: 0.09,
  /** Of the latest looks, how many must be that loud: about a tenth of a second of a voice, not a click. */
  recentBuffers: 5,
  loudBuffers: 4,
  /** Enough of its own speech heard to know how loud it comes back, about half a second. */
  enoughEcho: 24,
  /** What its echo is taken to be before any has been heard: a voice from the speakers at a normal volume. */
  unheardEcho: 0.5,
  /** The share of its own loudest moments ignored, since one peak is not how loud it usually comes back. */
  echoQuantile: 0.95,
  /** After its voice starts or comes back, how long loudness alone is not trusted, in milliseconds. */
  onsetGraceMs: 500,
  /** Looks in a row loudness alone must agree for with echo cancellation, where the room is the person. */
  loudLooksCancelling: 1,
  /** The same without it, about a third of a second, since its own echo is loud then and one look is a syllable. */
  loudLooksUncancelled: 3,
  /** Held at least this long, so the recognizer can still write words the person already said. */
  shortestHoldMs: 1_000,
  /** After its own sound has died away, the room this long below a voice means nobody is talking. */
  quietToCarryOnMs: 600,
  /** The longest a loud room with no words in it keeps it quiet, so a television cannot silence it for good. */
  longestHoldMs: 4_000,
  /** Loud enough playing to learn from how much of it comes back, rather than the hush between words. */
  playingFloor: 0.2,
  /** Looks at its own voice playing needed before how loud it comes back is trusted, about a second. */
  enoughLooks: 8,
  /** How much louder than its own echo the room must be, about seven decibels on the loudness scale. */
  overOwnMargin: 0.15,
  /** Looks in a row that must agree, so the tail of one of its words is not a person. */
  overOwnLooks: 2,
} as const;

/** One look at the room: how loud the microphone heard it, and how loud its own voice was playing then. */
export interface HeardLook {
  readonly heard: number;
  readonly playing: number;
}

/** How loud its own voice comes back, from the levels heard while it spoke, or what it was last time when too few. */
export function echoCeiling(heardWhileSpeaking: readonly number[], lastTime: number | undefined): number {
  if (heardWhileSpeaking.length < TALK_OVER.enoughEcho) {
    return Math.max(lastTime ?? TALK_OVER.unheardEcho, ...heardWhileSpeaking, 0);
  }
  const sorted = [...heardWhileSpeaking].sort((a, b) => a - b);
  const at = Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * TALK_OVER.echoQuantile));
  return sorted[at] ?? 0;
}

/** Whether the latest looks are somebody talking over it, louder than its own echo for long enough. */
export function isTalkingOver(recent: readonly number[], ceiling: number): boolean {
  return recent.slice(-TALK_OVER.recentBuffers).filter((level) => level >= ceiling + TALK_OVER.margin).length >= TALK_OVER.loudBuffers;
}

/** Whether loudness alone may pause the voice now: not just after it came on, and only once it has held. */
export function mayPauseOnLoudness(voiceOnForMs: number, loudLooks: number, cancellingEcho: boolean): boolean {
  return voiceOnForMs >= TALK_OVER.onsetGraceMs && loudLooks >= (cancellingEcho ? TALK_OVER.loudLooksCancelling : TALK_OVER.loudLooksUncancelled);
}

/** Whether to carry on talking after a pause: never while the room is loud as a voice, since that is the person. */
export function mayCarryOn(pausedForMs: number, quietForMs: number): boolean {
  return pausedForMs >= TALK_OVER.longestHoldMs || (pausedForMs >= TALK_OVER.shortestHoldMs && quietForMs >= TALK_OVER.quietToCarryOnMs);
}

/**
 * How much louder or quieter its voice comes back than it plays, from looks while it played, or last
 * time's when too few; undefined when nothing is known yet, since a guess would pause it on its own echo.
 */
export function ownVoiceGap(looks: readonly HeardLook[], lastTime: number | undefined): number | undefined {
  const gaps = looks
    .filter((look) => look.playing >= TALK_OVER.playingFloor)
    .map((look) => look.heard - look.playing)
    .sort((a, b) => a - b);
  if (gaps.length < TALK_OVER.enoughLooks) return lastTime;
  return gaps[Math.floor(gaps.length / 2)];
}

/**
 * Whether the latest looks are somebody talking over it: the room loud as a voice, and louder than its
 * own echo of what was playing then or a moment before, which tells the person from it without echo
 * cancellation, and in the hush between its words at once.
 */
export function isOverOwnVoice(looks: readonly HeardLook[], gap: number, talking: number): boolean {
  if (looks.length <= TALK_OVER.overOwnLooks) return false;
  for (let index = looks.length - TALK_OVER.overOwnLooks; index < looks.length; index += 1) {
    const look = looks[index];
    const before = looks[index - 1];
    if (look === undefined || before === undefined) return false;
    const playing = Math.max(look.playing, before.playing);
    if (!(look.heard >= talking && look.heard - playing >= gap + TALK_OVER.overOwnMargin)) return false;
  }
  return true;
}
