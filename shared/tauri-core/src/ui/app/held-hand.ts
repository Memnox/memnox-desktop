import type { HeldCalls, HeldState } from '../../core';
import { islandWindow, type HandedAnswer } from '../adapters/tauri-island-window';

/** The calls each queue handed the island and has not heard back on, so each hears the island once however many pages press. */
const handed = new WeakMap<HeldCalls, Set<string>>();

/**
 * Whether the answers on a page's held cards wait, as the Mac's `answering || settledNote != nil`: while an allow is
 * being signed, and while a card says how it was settled before it goes.
 */
export function heldBusy(state: HeldState): boolean {
  return state.answering || state.settled !== undefined;
}

/**
 * A page's answer to a held call, handed to the island the way the Mac's Approvals and Today hand theirs: the island
 * asks for the key, sends it, shakes on a failure and says on its own card when somebody answered first, and this
 * window's card leaves once the island says the answer stood. In a preview, with no island, the page answers itself.
 */
export function handHeld(calls: HeldCalls, subject: string, answer: HandedAnswer): void {
  if (heldBusy(calls.state)) return;
  let waiting = handed.get(calls);
  if (waiting === undefined) {
    const mine = new Set<string>();
    waiting = mine;
    handed.set(calls, mine);
    // Every window hears the island, so only the one that handed this call settles it.
    islandWindow.onHeldAnswered((answered, outcome) => {
      if (mine.delete(answered)) calls.handedBack(answered, outcome);
    });
  }
  if (!islandWindow.handHeld(subject, answer)) {
    void calls.answer(subject, answer);
    return;
  }
  waiting.add(subject);
  calls.handed(subject, answer);
}
