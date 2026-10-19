/** What the orb is doing, which decides how it moves. */
export type OrbState = 'idle' | 'listening' | 'thinking' | 'speaking' | 'needs-you';

/** A short gesture over whatever the state is doing: an allow rings out, a refusal pulls in. */
export type Reaction = 'burst' | 'stumble' | 'settle' | 'allowed' | 'refused' | 'glance';

/** Everything the shader reads each frame, in the order its uniforms are declared. */
export interface OrbUniforms {
  time: number;
  level: number;
  swirl: number;
  hold: number;
  burst: number;
  jitter: number;
  drain: number;
  pull: number;
  glow: number;
  bounce: number;
  knot: number;
  seal: number;
  ringHeights: [number, number, number, number];
  ringFades: [number, number, number, number];
}

const POINT_COUNT = 6_000;
/** The side at which every point draws at full size; smaller orbs thin them out. */
const FULL_SIZE_SIDE = 240;
const MINIMUM_POINTS = 300;
const MINIMUM_DOT_SHARE = 0.35;

/** Where each state eases the sphere toward: how much it ripples, spins and pulls in. */
const TARGET: Record<OrbState, { level: number; swirl: number; hold: number; gain: number }> = {
  idle: { level: 0.04, swirl: 0, hold: 0, gain: 0 },
  listening: { level: 0.08, swirl: 0, hold: 0, gain: 1 },
  thinking: { level: 0.12, swirl: 1, hold: 0, gain: 0 },
  // Speech ripples a little harder than the same loudness heard.
  speaking: { level: 0.1, swirl: 0, hold: 0, gain: 1.2 },
  'needs-you': { level: 0.02, swirl: 0, hold: 1, gain: 0 },
};

/** How much of the gap to its target each value closes per frame: ripples fast, spin and hold slowly. */
const EASING = { level: 0.25, swirl: 0.05, hold: 0.08, knot: 0.05, waiting: 0.06 };

/** The easings were tuned one step per frame at this rate, so a slower frame takes several steps, at most this many. */
const TUNED_FPS = 60;
const MOST_STEPS = 6;
/** Below this the bounce has settled and no longer needs every frame. */
const STILL = 0.01;

/** The voice's syllables, each a fast rise in loudness that sends a lit ring from chin to crown. */
const SYLLABLE = { attack: 0.55, release: 0.18, rise: 0.06, gap: 0.12, life: 1.2, most: 4, start: -1.15, climb: 2.1 };

/** How long each gesture lasts, in seconds, and the shares of it spent rising and holding. */
const GESTURE_SECONDS: Record<Reaction, number> = { burst: 2.2, stumble: 0.9, settle: 0.8, allowed: 0.7, refused: 0.6, glance: 0.5 };
const GESTURE_ATTACK = 0.15;
const SEAL_RISE = 0.25;
const SEAL_FALL = 0.3;
const SHARE = { settle: 0.18, allowed: 0.3, glance: 0.25 };

/** Fewer and finer points as the orb gets smaller, since full size dots on a small orb glow into a flat disc. */
export function orbFit(side: number): { points: number; dot: number } {
  const share = Math.min(1, Math.max(0, side / FULL_SIZE_SIDE));
  return { points: Math.floor(Math.max(MINIMUM_POINTS, POINT_COUNT * share * share)), dot: Math.max(MINIMUM_DOT_SHARE, share) };
}

/** Up quickly, held long enough to read, then let go, with eased corners so nothing snaps. */
function plateau(progress: number): number {
  const held = Math.max(0, Math.min(Math.min(1, progress / SEAL_RISE), Math.min(1, (1 - progress) / SEAL_FALL)));
  return held * held * (3 - 2 * held);
}

/**
 * The orb's motion, ported from the Mac's `OrbRenderer`: eased toward what each state wants so the
 * sphere breathes rather than twitches, with rings for syllables and short gestures over the top.
 * Every call takes the time in seconds, so a test drives the clock.
 */
export class OrbMotion {
  private level = 0;
  private swirl = 0;
  private hold = 0;
  private knot = 0;
  private bounce = 0;
  private voice = 0;
  private onsets: number[] = [];
  private gesture: { reaction: Reaction; at: number } | undefined;
  private lastFrame: number | undefined;
  /** How many tuned steps this frame stands for, so the sphere moves at one speed at any frame rate. */
  private steps = 1;
  private state: OrbState = 'idle';
  private waiting = false;

  constructor(private readonly started: number) {}

  react(reaction: Reaction, now: number): void {
    this.gesture = { reaction, at: now };
  }

  /** One frame: `loudness` from 0 to 1, `waiting` while a call waits on the person. */
  frame(now: number, state: OrbState, loudness: number, waiting: boolean): OrbUniforms {
    this.steps = Math.min((now - (this.lastFrame ?? now - 1 / TUNED_FPS)) * TUNED_FPS, MOST_STEPS);
    this.lastFrame = now;
    this.state = state;
    this.waiting = waiting;
    const heard = Math.min(Math.max(loudness, 0), 1);
    this.listen(heard, now, state);
    const target = TARGET[state];
    this.level += (target.level + heard * target.gain - this.level) * this.eased(EASING.level);
    this.swirl += (target.swirl - this.swirl) * this.eased(EASING.swirl);
    this.hold += (target.hold - this.hold) * this.eased(EASING.hold);
    this.knot += ((state === 'thinking' ? 1 : 0) - this.knot) * this.eased(EASING.knot);
    this.bounce += ((waiting ? 1 : 0) - this.bounce) * this.eased(EASING.waiting);
    const [ringHeights, ringFades] = this.rings(now);
    return {
      time: now - this.started,
      level: this.level,
      swirl: this.swirl,
      hold: this.hold,
      bounce: this.bounce,
      knot: this.knot,
      ...this.shape(now),
      ringHeights,
      ringFades,
    };
  }

  /** Whether nothing on the sphere moves but its slow breath, so fewer frames look the same. */
  resting(): boolean {
    return (this.state === 'idle' || this.state === 'needs-you') && !this.waiting && this.gesture === undefined
      && this.bounce < STILL && this.onsets.length === 0;
  }

  /** One frame's share of the gap, compounded over however many tuned steps the frame stands for. */
  private eased(rate: number): number {
    return 1 - Math.pow(1 - rate, this.steps);
  }

  /** Follows the voice envelope and marks a syllable wherever it jumps, only while the orb speaks. */
  private listen(heard: number, now: number, state: OrbState): void {
    const previous = this.voice;
    this.voice += (heard - this.voice) * this.eased(heard > this.voice ? SYLLABLE.attack : SYLLABLE.release);
    const last = this.onsets[this.onsets.length - 1];
    const rested = last === undefined || now - last > SYLLABLE.gap;
    if (state === 'speaking' && this.voice - previous > SYLLABLE.rise && rested) this.onsets.push(now);
    this.onsets = this.onsets.filter((onset) => now - onset < SYLLABLE.life).slice(-SYLLABLE.most);
  }

  /** Where each climbing ring is and how bright it still is, unused slots dark. */
  private rings(now: number): [OrbUniforms['ringHeights'], OrbUniforms['ringFades']] {
    const heights: OrbUniforms['ringHeights'] = [0, 0, 0, 0];
    const fades: OrbUniforms['ringFades'] = [0, 0, 0, 0];
    this.onsets.forEach((onset, slot) => {
      const age = now - onset;
      const left = Math.max(0, 1 - age / SYLLABLE.life);
      heights[slot] = SYLLABLE.start + age * SYLLABLE.climb;
      fades[slot] = left * left;
    });
    return [heights, fades];
  }

  /** The strength of each part of the gesture now: a quick rise, then an eased fall to nothing. */
  private shape(now: number): Pick<OrbUniforms, 'burst' | 'jitter' | 'drain' | 'pull' | 'glow' | 'seal'> {
    const none = { burst: 0, jitter: 0, drain: 0, pull: 0, glow: 0, seal: 0 };
    if (this.gesture === undefined) return none;
    const progress = (now - this.gesture.at) / GESTURE_SECONDS[this.gesture.reaction];
    if (progress >= 1) {
      this.gesture = undefined;
      return none;
    }
    const falling = (progress - GESTURE_ATTACK) / (1 - GESTURE_ATTACK);
    const envelope = progress < GESTURE_ATTACK ? progress / GESTURE_ATTACK : (1 - falling) * (1 - falling);
    switch (this.gesture.reaction) {
      case 'burst':
        return { ...none, burst: envelope, glow: envelope, seal: plateau(progress) };
      case 'stumble':
        return { ...none, jitter: envelope, drain: envelope };
      case 'settle':
        return { ...none, burst: envelope * SHARE.settle };
      case 'allowed':
        return { ...none, burst: envelope * SHARE.allowed, glow: envelope };
      case 'refused':
        return { ...none, pull: envelope };
      case 'glance':
        return { ...none, glow: envelope, pull: envelope * SHARE.glance };
    }
  }
}
