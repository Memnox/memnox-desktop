/** The island's own Settings panel, in its words. */
export const IslandSettingsLines = {
  voice: 'The voice it speaks in',
  agent: 'The agent it thinks with',
  askAgain: 'Ask each agent again',
  protect: 'Put my agents under Memnox',
} as const;

/** The voice install's words under the island, as the Mac's pill says them. */
export const TalkLines = {
  installingStep: (part: string, done: string) => `Installing the voice, ${part}: ${done}`,
  ofTotal: (total: string) => ` of ${total}`,
  installing: 'Installing the voice',
  notInstalled: 'The voice is not installed yet',
  tryAgain: 'Try again',
} as const;

/** A connected app's page in the launcher, in its words. */
export const ToolPageLines = {
  connected: 'Connected',
  needsSignIn: 'Needs a sign in',
  askHeading: 'ASK MEMNOX',
  askTitle: (words: string) => `Ask “${words}”`,
  askLabel: (words: string) => `Ask Memnox: ${words}`,
} as const;
