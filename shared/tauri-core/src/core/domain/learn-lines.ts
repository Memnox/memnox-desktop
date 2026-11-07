/** The Learn queue's own words. */
export const LearnLines = {
  readWhat: 'the Learn queue',
  emptyTitle: 'Nothing to confirm',
  emptyBody: 'When your agent reads a memory source, or another agent suggests something through memnox_suggest, it waits here until you confirm, edit or reject it.',
  waiting: (count: number) => `${count} waiting, oldest first. Nothing here reaches an agent as settled until you confirm it.`,
  signing: 'Waiting for your signature on the island',
  statement: 'The statement',
  governs: (sentence: string) => `What it would govern: ${sentence}`,
  save: 'Save',
  cancel: 'Cancel',
  confirm: 'Confirm',
  edit: 'Edit',
  reject: 'Reject',
  ruleProposes: (keyTitle: string) => `Confirming a rule proposes it. It holds once you sign it on the island with ${keyTitle}.`,
} as const;
