/** The few words the base components say themselves, so no control carries a sentence of its own. */
export const KitLines = {
  cancel: 'Cancel',
  close: 'Close',
  clear: 'Clear',
  working: 'Working',
  tryAgain: 'Try again',
  readFailed: (what: string) => `Memnox could not read ${what}.`,
} as const;
