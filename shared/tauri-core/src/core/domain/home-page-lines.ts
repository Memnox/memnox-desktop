/**
 * The words Home and Today put on screen around the daemon's own lines, kept here so a test can hold them to the
 * Mac's `HomeDestination`, `TodayDestination` and `HomeStart`, where the same words sit inline in `Text(...)`. Only
 * "Mac" becomes "computer" and Touch ID becomes this platform's key.
 */
export const HomePageLines = {
  lead: 'What your agents can do on their own, and what still needs you.',
  protecting: 'Runtime protecting this computer',
  away: 'The runtime is not answering',
  readFailed: 'the runtime',
  carryOn: 'Carry on',
};

/** The getting started block's own words, beside the steps that `home-steps` names. */
export const HomeStartLines = {
  label: 'What to do next',
  hiddenLabel: 'What to do next, hidden',
  doThisNext: 'DO THIS NEXT',
  show: 'Show',
  hide: 'Hide',
  showHelp: 'Show the steps again',
  hideHelp: 'Fold these steps to one line until you want them again',
  cancel: 'Cancel',
  /** "3 of 8 steps done", what a screen reader hears for the ring. */
  stepsDone: (completed: number, total: number) => `${completed} of ${total} steps done`,
  /** "Put your agents under Memnox, done", what a screen reader hears for one step. */
  step: (title: string, done: boolean) => `${title}, ${done ? 'done' : 'not yet'}`,
};

/** Today's table, strip and panel, in the Mac's words. */
export const TodayPageLines = {
  /** The table's head, the number's column first and unnamed. */
  columns: ['', 'What', 'From', 'When', 'State'] as const,
  activity: 'Activity',
  show: 'Show',
  hide: 'Hide',
  showAll: (count: number) => `Show all ${count}`,
  above: 'The item above',
  below: 'The item below',
  keys: 'Up and Down move, a letter decides, Escape closes',
  recommendation: 'RECOMMENDATION',
  decide: 'DECIDE',
  recommended: 'Recommended',
  from: 'From',
  waiting: 'Waiting',
  project: 'Project',
  about: 'About',
  signed: 'Signed',
  /** "Press A", the hint on a choice. */
  press: (key: string) => `Press ${key}`,
};

/** How a yes to a held call is signed, as the Mac's `HeldSigning.line` says it with this platform's key. */
export function heldSigningLine(touchID: boolean, actionDigest: string | undefined, keyTitle: string): string {
  if (!touchID) return 'Inside its own repository, so a yes needs no signature';
  if (actionDigest === undefined) return `A yes is signed with ${keyTitle}`;
  return `A yes is signed with ${keyTitle} over exactly this call, so one changed since is refused`;
}

/** Today's table widths in points, the Mac's `WorkTable` measures, so both desktops cut the columns alike. */
export const TODAY_TABLE = { number: 28, from: 170, when: 72, state: 118, logo: 20, head: 34 } as const;
