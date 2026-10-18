import { HOLD_ANSWER, type HoldAnswer } from '@memnox/core/wire';

/**
 * "Allow from now on": the daemon runs the call once and puts a narrow rule on a card to place and
 * sign. The runtime takes the word on a confirm beside the three in `HOLD_ANSWER`, which does not list it.
 */
export const FROM_NOW_ON = 'always';

/** Every answer a held call takes from a button here, the Mac's `HoldAnswer` with `always`. */
export type HeldAnswer = HoldAnswer | typeof FROM_NOW_ON;

/** How every label names the computer the app runs on. */
export const THIS_COMPUTER = 'this computer';
const SOME_AGENT = 'an agent';

/** Undefined for nothing but spaces, so a blank name never makes "on ". */
export function trimmed(text: string | undefined): string | undefined {
  const kept = text?.trim();
  return kept === undefined || kept === '' ? undefined : kept;
}

const SOME_SERVER = 'a server';
const SOME_MACHINE = "a teammate's machine";

/** Where a held call waits, which is what every label of it names. Ported from the Mac's `CallPlace`. */
export type CallPlace =
  | { readonly kind: 'this-computer' }
  /** A server this computer paired with over the relay, by the name it paired under. */
  | { readonly kind: 'server'; readonly name: string }
  /** A teammate's machine the workspace routed the call from, with whose team it is when the workspace says. */
  | { readonly kind: 'team'; readonly machine: string; readonly person: string | undefined };

export const ON_THIS_COMPUTER: CallPlace = { kind: 'this-computer' };

/** A daemon event's place: the server that raised it, or this computer when none did. */
export function raisedOn(server: string | undefined): CallPlace {
  const name = trimmed(server);
  return name === undefined ? ON_THIS_COMPUTER : { kind: 'server', name };
}

export function teamPlace(machine: string, person: string | undefined): CallPlace {
  return { kind: 'team', machine, person };
}

/** The machine alone, as the island groups waiting calls by it. */
export function placeMachine(place: CallPlace): string {
  switch (place.kind) {
    case 'this-computer':
      return THIS_COMPUTER;
    case 'server':
      return trimmed(place.name) ?? SOME_SERVER;
    case 'team':
      return trimmed(place.machine) ?? SOME_MACHINE;
  }
}

/**
 * One label for a held call wherever it shows: "codex on this computer", "codex on build-box", and
 * "codex on build-box, from Ana's team" through the workspace. Ported from the Mac's `CallLabel`.
 */
export function callLabel(agent: string | undefined, at: string | CallPlace = THIS_COMPUTER): string {
  const place = typeof at === 'string' ? undefined : at;
  const named = `${trimmed(agent) ?? SOME_AGENT} on ${place === undefined ? at : placeMachine(place)}`;
  if (place?.kind !== 'team') return named;
  const person = trimmed(place.person);
  // Whose team it came through, and the person's own team where the workspace did not say whose.
  return `${named}, ${person === undefined ? 'from your team' : `from ${person}'s team`}`;
}

/** What the consent prompt says it is for, so the person answers knowing whose call and how far the yes reaches. */
export function consentReason(label: string, what: string | undefined, answer: HeldAnswer): string {
  const reach = REACH[answer](label);
  const phrase = trimmed(what);
  if (phrase === undefined) return reach;
  // A full stop inside the prompt's sentence reads as the end of it, so the last one goes.
  return `${reach}: ${phrase.endsWith('.') ? phrase.slice(0, -1) : phrase}`;
}

const REACH: Record<HeldAnswer, (label: string) => string> = {
  [HOLD_ANSWER.ONCE]: (label) => `allow ${label} once`,
  [HOLD_ANSWER.SESSION]: (label) => `allow ${label} for this session`,
  [HOLD_ANSWER.DENY]: (label) => `deny ${label}`,
  [HOLD_ANSWER.EDIT]: (label) => `send ${label} back to fix its command`,
  [FROM_NOW_ON]: (label) => `allow ${label} now, and put a rule for from now on to you`,
};
