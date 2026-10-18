/**
 * The island's modes, sizes and timings, and the one rule that picks the mode, ported from the Mac's
 * `IslandLayout.swift` and `IslandModel.settle()`. Pure numbers, so every screen and every test reads
 * the same measurements and the UI only animates between them.
 */

/** Every face the island can take, smallest first as the Mac lists them. */
export type IslandMode =
  | 'peek'
  | 'compact'
  | 'voice'
  | 'hearing'
  | 'overview'
  | 'session'
  | 'empty'
  | 'held'
  | 'question'
  | 'finished'
  | 'launcher'
  | 'conversation'
  | 'draft'
  | 'answer'
  | 'rule';

/** Where the notch is, or the small bar standing in for one on a screen without it. */
export interface NotchGeometry {
  readonly width: number;
  readonly height: number;
}

/** Windows and Linux have no notch, so they take the Mac's stand in bar: this wide, and no taller than 24. */
export const STAND_IN_NOTCH: NotchGeometry = { width: 80, height: 24 };

export interface Size {
  readonly width: number;
  readonly height: number;
}

export interface OrbSpot {
  /** Measured from the island body's left edge, inside the flare. */
  readonly x: number;
  readonly y: number;
  readonly diameter: number;
}

/** The measurements the island is drawn with, one name each so no screen carries a bare number. */
export const ISLAND = {
  /** Wide enough for two cards side by side and no wider. */
  width: 560,
  /** The concave curve where the island meets the screen edge on either side. */
  flare: 14,
  /** How far an open island's content sits in from its sides and bottom. */
  contentInset: 10,
  voiceWidth: 440,
  voiceOrb: 150,
  openBottomRadius: 30,
  closedBottomRadius: 14,
  /** The orb fills this share of its canvas, leaving the rest for its bursts and glow. */
  orbCanvasShare: 0.62,
  /** The pointer counts as over the island this far outside its shape. */
  pointerSlop: 6,
  /** The space between the island and each pill hanging under it. */
  pillGap: 6,
} as const;

/** The round buttons either side of the open island. */
export const SATELLITE = {
  diameter: 44,
  gap: 12,
  step: 54,
  /** Below the notch row, so a top panel never hides the top pair. */
  gapBelowNotch: 6,
  /** How far they reach out from the island on each side, for the window and its clicks. */
  reach: 12 + 44,
} as const;

/** The launcher's tiles, which size its mode. */
export const TILE = { width: 92, height: 86, spacing: 8, columns: 5, radius: 16 } as const;

/** The window the island grows inside: the widest island, both flares, a margin and both satellite columns. */
export const ISLAND_WINDOW: Size = {
  width: ISLAND.width + 2 * ISLAND.flare + 40 + 2 * SATELLITE.reach,
  // The tallest island, the opened answer, and room under it for the pills that hang below.
  height: 560 + 112,
};

/** How long things wait and stay, in milliseconds, as the Mac times them. */
export const ISLAND_TIMING = {
  /** Long enough that passing the pointer across the top of the screen never opens it. */
  dwellResting: 650,
  dwellBusy: 200,
  /** Open and untouched this long, it puts itself away; the last ten seconds show as a shrinking line. */
  idleClose: 60_000,
  countdownFrom: 10_000,
  finishedFor: 5_200,
  phoneTurnFor: 8_000,
  /** Long enough to read one short line saying the call was settled elsewhere. */
  settledFor: 2_800,
  stumbleFor: 900,
} as const;

/** Each open mode's height, just tall enough for what it holds. */
const HEIGHT = {
  voiceBelowTop: 190,
  overview: 196,
  session: 256,
  empty: 150,
  held: 206,
  question: 372,
  finished: 170,
  launcher: 230,
  hearingBelowTop: 196,
  conversation: 372,
  draft: 430,
  answer: 560,
  rule: 470,
} as const;

/** How much wider than the notch the small modes are, leaving room for the orb and the session logos. */
const WIDENING = { peek: 64, compact: 104 } as const;

const WIDTH = {
  hearing: 500,
  conversation: 540,
  launcher: TILE.width * TILE.columns + TILE.spacing * (TILE.columns - 1) + 2 * ISLAND.contentInset,
} as const;

/** Content never starts above this, and always a little below the notch itself. */
const MINIMUM_TOP = 36;
const GAP_BELOW_NOTCH = 4;

/** Where content starts below the notch row, which is also where the header sits. */
export function islandTop(notch: NotchGeometry): number {
  return Math.max(MINIMUM_TOP, notch.height + GAP_BELOW_NOTCH);
}

export function islandSize(mode: IslandMode, notch: NotchGeometry): Size {
  switch (mode) {
    case 'peek':
      return { width: notch.width + WIDENING.peek, height: notch.height };
    case 'compact':
      return { width: notch.width + WIDENING.compact, height: notch.height };
    case 'voice':
      return { width: ISLAND.voiceWidth, height: islandTop(notch) + HEIGHT.voiceBelowTop };
    case 'hearing':
      return { width: WIDTH.hearing, height: islandTop(notch) + HEIGHT.hearingBelowTop };
    case 'overview':
      return { width: ISLAND.width, height: HEIGHT.overview };
    case 'session':
      return { width: ISLAND.width, height: HEIGHT.session };
    case 'empty':
      return { width: ISLAND.width, height: HEIGHT.empty };
    case 'held':
      return { width: ISLAND.width, height: HEIGHT.held };
    case 'question':
      return { width: ISLAND.width, height: HEIGHT.question };
    case 'finished':
      return { width: ISLAND.width, height: HEIGHT.finished };
    case 'launcher':
      return { width: WIDTH.launcher, height: HEIGHT.launcher };
    case 'conversation':
      return { width: WIDTH.conversation, height: HEIGHT.conversation };
    case 'draft':
      return { width: WIDTH.conversation, height: HEIGHT.draft };
    case 'answer':
      return { width: ISLAND.width, height: HEIGHT.answer };
    case 'rule':
      return { width: WIDTH.conversation, height: HEIGHT.rule };
  }
}

/** Peek and compact sit beside the notch; every other mode is the island opened. */
export function isOpenMode(mode: IslandMode): boolean {
  return mode !== 'peek' && mode !== 'compact';
}

/** Growing springs out and shrinking eases in, and which one it is goes by area, as on the Mac. */
export function isGrowing(from: IslandMode, to: IslandMode, notch: NotchGeometry): boolean {
  const area = (mode: IslandMode) => {
    const size = islandSize(mode, notch);
    return size.width * size.height;
  };
  return area(to) > area(from);
}

/** The orb's place in each mode: beside the notch when small, left of the content when open. */
const ORB = {
  peek: { x: 19, diameter: 18, hover: 22 },
  compact: { x: 27, diameter: 20, hover: 23 },
  voiceBelowTop: 92,
  overview: { x: 54, diameter: 58 },
  empty: { x: 70, diameter: 62 },
  held: { x: 62, diameter: 56 },
  finished: { x: 62, diameter: 58 },
  hearing: { belowTop: 50, diameter: 84 },
  /** In the header row left of the notch, a small light while the words take the space below. */
  header: { x: 30, diameter: 20 },
} as const;

/** The orb's centre and diameter in each mode, so it travels and grows with the island as one piece. */
export function orbSpot(mode: IslandMode, notch: NotchGeometry, hovering: boolean): OrbSpot {
  const height = islandSize(mode, notch).height;
  const top = islandTop(notch);
  const middle = top + (height - top - ISLAND.contentInset) / 2;
  switch (mode) {
    case 'peek':
      return { x: ORB.peek.x, y: notch.height / 2, diameter: hovering ? ORB.peek.hover : ORB.peek.diameter };
    case 'compact':
      return { x: ORB.compact.x, y: notch.height / 2, diameter: hovering ? ORB.compact.hover : ORB.compact.diameter };
    case 'voice':
      return { x: ISLAND.voiceWidth / 2, y: top + ORB.voiceBelowTop, diameter: ISLAND.voiceOrb };
    case 'hearing':
      return { x: WIDTH.hearing / 2, y: top + ORB.hearing.belowTop, diameter: ORB.hearing.diameter };
    case 'overview':
      return { x: ORB.overview.x, y: middle, diameter: ORB.overview.diameter };
    case 'empty':
      return { x: ORB.empty.x, y: middle, diameter: ORB.empty.diameter };
    case 'held':
      return { x: ORB.held.x, y: middle, diameter: ORB.held.diameter };
    case 'finished':
      return { x: ORB.finished.x, y: middle, diameter: ORB.finished.diameter };
    // A question gives the agent and its choices the whole width, so the orb waits in the header.
    case 'session':
    case 'conversation':
    case 'draft':
    case 'answer':
    case 'rule':
    case 'launcher':
    case 'question':
      return { x: ORB.header.x, y: notch.height / 2, diameter: ORB.header.diameter };
  }
}

/** The header holds the title and the count, except while talking, when the words take the room. */
export function showsHeader(mode: IslandMode, active: boolean): boolean {
  switch (mode) {
    case 'hearing':
    case 'conversation':
    case 'draft':
    case 'rule':
    case 'peek':
    case 'compact':
      return false;
    case 'answer':
      return !active;
    case 'voice':
    case 'overview':
    case 'session':
    case 'empty':
    case 'held':
    case 'question':
    case 'finished':
    case 'launcher':
      return true;
  }
}

/** The round buttons go with the header, so they never crowd the words while talking. */
export function showsSatellites(mode: IslandMode, active: boolean): boolean {
  return showsHeader(mode, active) && mode !== 'voice';
}

/** The small orb sits at the start of the header in these modes, so the title starts past it. */
export function headerPastOrb(mode: IslandMode): boolean {
  return mode === 'answer' || mode === 'session' || mode === 'launcher' || mode === 'question';
}

/** What the header row is named in each mode; the launcher and session detail pass their own words. */
export function islandTitle(mode: IslandMode, named: { session?: string; launcher?: string } = {}): string {
  switch (mode) {
    case 'overview':
      return 'Sessions';
    case 'empty':
      return 'Memnox';
    case 'session':
      return named.session ?? 'Session';
    case 'launcher':
      return named.launcher ?? 'Memnox';
    case 'held':
      return 'Needs you';
    case 'question':
      return 'A question';
    case 'finished':
      return 'Finished';
    case 'voice':
      return 'Listening';
    case 'answer':
      return 'Answer';
    case 'peek':
    case 'compact':
    case 'hearing':
    case 'conversation':
    case 'draft':
    case 'rule':
      return '';
  }
}

/** The idle countdown runs only on the screens a person opened to look at. */
export function countsDown(mode: IslandMode): boolean {
  return mode === 'overview' || mode === 'session' || mode === 'empty' || mode === 'answer';
}

/** How long the pointer rests on the closed island before it opens: longer at rest, shorter while busy. */
export function dwellFor(mode: IslandMode): number {
  return mode === 'peek' ? ISLAND_TIMING.dwellResting : ISLAND_TIMING.dwellBusy;
}

/**
 * How much of the countdown line is left, from one to nothing, or undefined while it is not shown;
 * `closes` says the minute is up. Pure, so a test sets the clock.
 */
export function idleCountdown(untouchedMs: number): { fraction: number | undefined; closes: boolean } {
  const left = ISLAND_TIMING.idleClose - untouchedMs;
  if (left <= 0) return { fraction: undefined, closes: true };
  return { fraction: left < ISLAND_TIMING.countdownFrom ? left / ISLAND_TIMING.countdownFrom : undefined, closes: false };
}

/** Everything `settle` reads, each a plain fact so the rule is tested without a window. */
export interface IslandFacts {
  readonly held: boolean;
  readonly question: boolean;
  /** A draft or a work card waiting to be sent. */
  readonly draft: boolean;
  readonly rule: boolean;
  readonly finished: boolean;
  /** A voice turn of the person's own is under way. */
  readonly talking: boolean;
  readonly dictating: boolean;
  readonly ruling: boolean;
  /** Live words are on and some have been heard. */
  readonly wordsHeard: boolean;
  readonly phoneTurn: boolean;
  readonly opened: boolean;
  readonly launcher: boolean;
  readonly pickedAnswer: boolean;
  readonly sessions: number;
  /** The person asked for one session up close and it has been read. */
  readonly detail: boolean;
  readonly working: number;
}

/** No facts at all: the island at rest. */
export const RESTING: IslandFacts = {
  held: false,
  question: false,
  draft: false,
  rule: false,
  finished: false,
  talking: false,
  dictating: false,
  ruling: false,
  wordsHeard: false,
  phoneTurn: false,
  opened: false,
  launcher: false,
  pickedAnswer: false,
  sessions: 0,
  detail: false,
  working: 0,
};

/** The one place the mode is decided, first match wins, so no two callers disagree about what is on screen. */
export function settle(facts: IslandFacts): IslandMode {
  if (facts.held) return 'held';
  // An agent is blocked on it as on a held call, so it shows while the voice reads it out too.
  if (facts.question) return 'question';
  if (facts.draft) return 'draft';
  if (facts.rule) return 'rule';
  if (facts.finished) return 'finished';
  // A rule is always shown as it is said, since the person signs it.
  if (facts.talking) return facts.ruling || facts.dictating || facts.wordsHeard ? 'hearing' : 'voice';
  // The person talking here comes first; a phone's turn is only watched, so it waits behind them.
  if (facts.phoneTurn) return 'conversation';
  if (facts.opened && facts.launcher) return 'launcher';
  if (facts.opened && facts.pickedAnswer) return 'answer';
  if (facts.opened) return facts.sessions === 0 ? 'empty' : facts.detail ? 'session' : 'overview';
  return facts.working === 0 ? 'peek' : 'compact';
}
