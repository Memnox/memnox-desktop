import { cutInWords, isPersonAfterPause, mayBeCuttingIn, sincePause, withoutEcho } from '../domain/echo';
import { echoCeiling, isOverOwnVoice, isTalkingOver, mayCarryOn, mayPauseOnLoudness, ownVoiceGap, TALK_OVER, type HeardLook } from '../domain/talk-over';
import { endOfSpeechPause, joinedSpeech } from '../domain/turn-taking';
import { nameAlone } from '../domain/wake-word';

/** What the watch reaches through: what the voice said lately, whether it is speaking, and its controls. */
export interface TalkOverDeps {
  spoken(): string;
  speaking(): boolean;
  hush(): void;
  carryOn(): void;
  /** The person cut in: the voice and the brain stop now. */
  cutIn(): void;
  now(): number;
}

/** Loud enough to be somebody talking near the computer: speech reads about 0.4 to 0.6, a quiet room under 0.1. */
const TALKING_LEVEL = 0.3;
/** About a third of a second of it, so a cough or a door is not taken for a sentence. */
const TALKING_LOOKS = 3;
/** How long its own sound takes to die away in the room once it is hushed. */
const ECHO_FADE_MS = 250;
/** About five seconds of looks at the room against what it played, so the gap follows a change of volume. */
const LOOKS_KEPT = 40;
/** A few more than the talk over check reads, so a late look still sees the newest. */
const RECENT_KEPT = TALK_OVER.recentBuffers * 2;
/** About five seconds of its own voice, so the echo follows a change of volume. */
const ECHO_KEPT = 240;

/** How loud its own voice came back last time, so the next reply knows the room from its first syllable. */
let lastEcho: number | undefined;
let lastGap: number | undefined;

/**
 * Listens while the voice thinks and talks, so the person can cut in just by speaking, ported from the
 * Mac's `BargeEars`. Their voice louder than its own echo, or a first word of theirs, pauses it at once;
 * more of them stops it, and quiet carries on. It reads loudness and spellings, never meaning.
 */
export class TalkOverWatch {
  private finals = '';
  private partial = '';
  private wordsChangedAt: number;
  private final = false;
  private recent: number[] = [];
  private echo: number[] = [];
  private looks: HeardLook[] = [];
  private loudSince: number | undefined;
  private loudCount = 0;
  private lastLoud: number | undefined;
  private voiceOnSince: number | undefined;
  private loudLooks = 0;
  private pausedAt: number | undefined;
  private pausedOn = '';
  private resumedOn = '';
  private spokeInQuiet = false;
  private cut = false;

  constructor(private readonly deps: TalkOverDeps) {
    this.wordsChangedAt = deps.now();
    this.countFrom(deps.now());
  }

  /** Whether the person cut in, so their sentence is waited for. */
  get barged(): boolean {
    return this.cut;
  }

  /** Everything heard so far in this watch, as one text. */
  get words(): string {
    return joinedSpeech(this.finals, this.partial);
  }

  level(heard: number, playing: number): void {
    const at = this.deps.now();
    if (heard >= TALKING_LEVEL) {
      this.lastLoud = at;
      if (this.loudSince !== undefined && at >= this.loudSince) this.loudCount += 1;
    }
    this.recent = [...this.recent, heard].slice(-RECENT_KEPT);
    if (this.deps.speaking()) {
      this.echo = [...this.echo, heard].slice(-ECHO_KEPT);
      this.looks = [...this.looks, { heard, playing }].slice(-LOOKS_KEPT);
    }
  }

  heard(text: string, final: boolean): void {
    if (final) {
      this.finals = joinedSpeech(this.finals, text);
      this.partial = '';
    } else {
      this.partial = text;
    }
    this.final = final;
    this.wordsChangedAt = this.deps.now();
  }

  /**
   * One look, about every 120 ms: pauses, carries on or cuts in. Returns the person's words once they
   * cut in and finished their sentence, an empty string when they cut in with nothing left of theirs,
   * and undefined while there is nothing to hand over yet.
   */
  look(): string | undefined {
    const now = this.deps.now();
    const words = this.words;
    const spoken = this.deps.spoken();
    const voiceOn = this.deps.speaking();
    if (!voiceOn) {
      this.voiceOnSince = undefined;
      this.loudLooks = 0;
    } else if (this.voiceOnSince === undefined) {
      this.voiceOnSince = now;
    }
    if (this.echo.length >= TALK_OVER.enoughEcho) lastEcho = echoCeiling(this.echo, undefined);
    const gap = ownVoiceGap(this.looks, lastGap);
    if (this.looks.length >= TALK_OVER.enoughLooks && gap !== undefined) lastGap = gap;
    if (!this.cut) this.decide(now, words, spoken, voiceOn, gap);
    // Once they have cut in, their whole sentence is kept until they pause.
    if (this.cut && (this.final || now - this.wordsChangedAt > endOfSpeechPause(words))) {
      return cutInWords(words, this.pausedOn, spoken, this.spokeInQuiet).trim();
    }
    return undefined;
  }

  /** Never left hushed when the watch ends, or the voice would stay quiet with nobody to wake it. */
  end(): void {
    if (this.pausedAt !== undefined) this.deps.carryOn();
    this.pausedAt = undefined;
  }

  private decide(now: number, words: string, spoken: string, voiceOn: boolean, gap: number | undefined): void {
    if (this.pausedAt !== undefined) {
      // The voice is quiet now, so sound loud enough to be speech with a word of theirs in it is them.
      const since = sincePause(words, this.pausedOn);
      const theirs = withoutEcho(since, spoken);
      const talking = this.loudCount >= TALKING_LOOKS && theirs !== '';
      if (talking || isPersonAfterPause(since, spoken)) {
        this.cut = true;
        this.pausedAt = undefined;
        this.deps.cutIn();
        return;
      }
      const quietFrom = Math.max(this.lastLoud ?? 0, this.pausedAt + ECHO_FADE_MS);
      if (mayCarryOn(now - this.pausedAt, now - quietFrom)) {
        this.pausedAt = undefined;
        this.resumedOn = words;
        this.deps.carryOn();
      }
      return;
    }
    if (voiceOn) {
      // Its own sound is loud too, so only what comes once it has died away is counted as them.
      this.countFrom(now + ECHO_FADE_MS);
      const ceiling = echoCeiling(this.echo, lastEcho);
      const loudNow = isTalkingOver(this.recent, ceiling) || (gap !== undefined && isOverOwnVoice(this.looks, gap, TALKING_LEVEL));
      this.loudLooks = loudNow ? this.loudLooks + 1 : 0;
      // There is no echo cancellation in the Windows and Linux audio path, so loudness has to hold longer.
      const louder = mayPauseOnLoudness(now - (this.voiceOnSince ?? now), this.loudLooks, false);
      if (louder || (words !== this.resumedOn && mayBeCuttingIn(words, spoken))) {
        // Paused rather than stopped, since a sound or a word of its own misheard looks the same at first.
        this.pausedAt = now;
        this.pausedOn = words;
        this.deps.hush();
      }
      return;
    }
    // Never on its name alone, which while it thinks is them checking it heard.
    if (words !== this.resumedOn && !nameAlone(words) && mayBeCuttingIn(words, spoken)) {
      this.spokeInQuiet = true;
      // Talking while it thinks is the question changing, so the old answer is dropped.
      if (this.loudCount >= TALKING_LOOKS) {
        this.cut = true;
        this.deps.cutIn();
      }
    }
  }

  /** Loud looks are counted from a moment on, so its own echo dying away is not counted as the person. */
  private countFrom(at: number): void {
    if (this.loudSince === undefined || at > this.loudSince) {
      this.loudSince = at;
      this.loudCount = 0;
    }
  }
}
