/** Where one step of setup stands, shown as a tick, a dashed ring, or what to do next, as the Mac's `StepState`. */
export type StepState = { kind: 'waiting' } | { kind: 'done' } | { kind: 'needs'; why: string };

export const WAITING: StepState = { kind: 'waiting' };
export const DONE: StepState = { kind: 'done' };

export function needs(why: string): StepState {
  return { kind: 'needs', why };
}

export function isDone(state: StepState): boolean {
  return state.kind === 'done';
}
