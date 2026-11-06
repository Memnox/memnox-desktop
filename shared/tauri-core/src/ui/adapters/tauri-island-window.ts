import { invoke } from '@tauri-apps/api/core';
import { emit, emitTo, listen } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';
import { HOLD_ANSWER } from '@memnox/core/wire';
import type { HandedOutcome } from '../../core/application/held-calls';
import { FROM_NOW_ON } from '../../core/domain/call-label';
import { TAURI_COMMAND } from './tauri-commands';

/** Told to the island by the side panel when an exchange is picked there, to open it tall. */
const PICKED_EVENT = 'side-exchange';
/** Told by Rust when a press lands outside every window of this app, which puts the open island away. */
const OUTSIDE_EVENT = 'island-outside';
/** Told to the island by Settings, whose home's Answer opens it on what waits. */
const ISLAND_OPEN_EVENT = 'island-open';
/** Told to the island by a page that answered a held call, so the island signs and sends it as for its own press. */
const HELD_HANDED_EVENT = 'held-handed';
/** Told back by the island once that answer ended, so the page that pressed settles its card. */
const HELD_ANSWERED_EVENT = 'held-answered';

/** The answers a page offers on a held call, never an edit, which only the island's own card makes. */
export type HandedAnswer = typeof HOLD_ANSWER.ONCE | typeof HOLD_ANSWER.SESSION | typeof HOLD_ANSWER.DENY | typeof FROM_NOW_ON;
const HANDED_ANSWERS: readonly string[] = [HOLD_ANSWER.ONCE, HOLD_ANSWER.SESSION, HOLD_ANSWER.DENY, FROM_NOW_ON];
const HANDED_KINDS: readonly string[] = ['answered', 'answered-elsewhere', 'cancelled', 'failed'];

/** A handed answer as the island reads it, nothing at all unless every field is what a page sends. */
function handedOf(payload: unknown): { subject: string; answer: HandedAnswer } | undefined {
  if (typeof payload !== 'object' || payload === null) return undefined;
  const { subject, answer } = payload as { subject?: unknown; answer?: unknown };
  if (typeof subject !== 'string' || subject === '' || typeof answer !== 'string' || !HANDED_ANSWERS.includes(answer)) return undefined;
  return { subject, answer: answer as HandedAnswer };
}

/** The island's word on a handed answer as the page reads it, nothing unless it is one the island sends. */
function answeredOf(payload: unknown): { subject: string; outcome: HandedOutcome } | undefined {
  if (typeof payload !== 'object' || payload === null) return undefined;
  const { subject, outcome } = payload as { subject?: unknown; outcome?: { kind?: unknown; word?: unknown; why?: unknown } };
  if (typeof subject !== 'string' || typeof outcome !== 'object' || outcome === null || typeof outcome.kind !== 'string' || !HANDED_KINDS.includes(outcome.kind)) return undefined;
  switch (outcome.kind) {
    case 'answered-elsewhere':
      return { subject, outcome: typeof outcome.word === 'string' ? { kind: 'answered-elsewhere', word: outcome.word } : { kind: 'answered-elsewhere' } };
    case 'failed':
      return { subject, outcome: { kind: 'failed', why: typeof outcome.why === 'string' ? outcome.why : '' } };
    default:
      return { subject, outcome: { kind: outcome.kind as 'answered' | 'cancelled' } };
  }
}

/** A box in the island window's own CSS pixels, top left at the window's top left. */
export interface HitArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** True inside the Tauri app, false in the preview page, where there is no window to tell. */
const inTauri = (): boolean => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/**
 * The island window as Rust holds it: the webview says where its shape, its pills and its satellites
 * are, and Rust lets every click elsewhere fall through to the window underneath.
 */
export const islandWindow = {
  /** Where clicks are taken; everywhere else they pass through. */
  setHitAreas(areas: readonly HitArea[], resting?: boolean): void {
    if (inTauri()) void invoke(TAURI_COMMAND.islandHitAreas, { areas, resting }).catch(() => undefined);
  },

  /** Takes the keyboard for this window, or gives it back to where the person was typing. */
  keyboard(on: boolean): void {
    if (inTauri()) void invoke(TAURI_COMMAND.islandKeyboard, { on }).catch(() => undefined);
  },

  /**
   * Hears when the pointer leaves or reaches the island while the window ignores the mouse, since the
   * webview sees no pointer events then and so never hears it leave.
   */
  onPointer(listener: (over: boolean) => void): () => void {
    if (!inTauri()) return () => undefined;
    // Heard on this window alone, since the side panel and the card wall are followed the same way.
    const stop = getCurrentWebviewWindow().listen<{ over: boolean }>('island-pointer', (event) => listener(event.payload.over));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** The side panel hands the island the exchange picked there, by its id in the shared history. */
  pick(id: string): void {
    if (inTauri()) void emitTo('island', PICKED_EVENT, id).catch(() => undefined);
  },

  onPicked(listener: (id: string) => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen<string>(PICKED_EVENT, (event) => listener(event.payload));
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** Asks the island to open on what waits, from Settings; nothing in a preview, where there is no island. */
  openFromSettings(): void {
    if (inTauri()) void emitTo('island', ISLAND_OPEN_EVENT).catch(() => undefined);
  },

  /**
   * A page's answer to a held call, handed to the island so it is signed, sent and its result shown there, as the Mac's
   * pages hand theirs to its island. False in a preview, where no island runs and the page answers itself.
   */
  handHeld(subject: string, answer: HandedAnswer): boolean {
    if (!inTauri()) return false;
    void emitTo('island', HELD_HANDED_EVENT, { subject, answer }).catch(() => undefined);
    return true;
  },

  /** The island hears each answer a page handed it. */
  onHeldHanded(listener: (subject: string, answer: HandedAnswer) => void): () => void {
    if (!inTauri()) return () => undefined;
    // Heard the way the side panel's pick is, since both are told to the island by its label.
    const stop = listen<unknown>(HELD_HANDED_EVENT, (event) => {
      const handed = handedOf(event.payload);
      if (handed !== undefined) listener(handed.subject, handed.answer);
    });
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** The island says how a handed answer ended, to every window, since only the one that pressed holds it. */
  tellHeldAnswered(subject: string, outcome: HandedOutcome): void {
    if (inTauri()) void emit(HELD_ANSWERED_EVENT, { subject, outcome }).catch(() => undefined);
  },

  onHeldAnswered(listener: (subject: string, outcome: HandedOutcome) => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen<unknown>(HELD_ANSWERED_EVENT, (event) => {
      const answered = answeredOf(event.payload);
      if (answered !== undefined) listener(answered.subject, answered.outcome);
    });
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** The displays the island can hang from and the one chosen, for the Appearance page. */
  screens(): Promise<{ chosen: string; displays: { id: string; name: string }[] }> {
    return inTauri() ? invoke(TAURI_COMMAND.islandScreens) : Promise.resolve({ chosen: 'notch', displays: [] });
  },

  chooseScreen(stored: string): Promise<void> {
    return inTauri() ? invoke(TAURI_COMMAND.islandScreenChoose, { stored }) : Promise.resolve();
  },

  /** Settings asks the island to open, for the home's Answer. */
  onOpenAsked(listener: () => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = listen(ISLAND_OPEN_EVENT, () => listener());
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },

  /** A press in another app, which a window of ours hears only from Rust, since the press never reaches it. */
  onOutsidePress(listener: () => void): () => void {
    if (!inTauri()) return () => undefined;
    const stop = getCurrentWebviewWindow().listen(OUTSIDE_EVENT, () => listener());
    return () => void stop.then((unlisten) => unlisten(), () => undefined);
  },
};
