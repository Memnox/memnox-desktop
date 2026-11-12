/**
 * What the island, its cards, the live session and the side panel say, in the Mac's words, so no view carries a
 * sentence of its own.
 */

/** A held call's answers and what a press came to, said the same on every card that holds one. */
export const HeldLines = {
  moreAnswers: 'More answers',
  olderCall: 'An older call',
  newerCall: 'A newer call',
  cancelled: 'Nothing was sent, so it is still waiting.',
  failed: (why: string) => `That did not go through: ${why}`,
} as const;

/** The finished and empty cards. */
export const CardLines = {
  open: 'Open',
  ok: 'OK',
  nothingRunning: 'Nothing is running right now.',
  talk: 'Talk to Memnox',
} as const;

/** The rule a person said, read back on its card before it is signed. */
export const RuleCardLines = {
  title: 'New rule',
  where: 'Where should it hold?',
  notNow: 'Not now',
  enforce: 'Enforce',
  proposeTeam: 'Propose for the team',
  enforceIn: (place: string) => `Enforce ${place}`,
  inFolder: (folder: string) => `in ${folder}`,
  forTeam: 'for the team',
  onComputer: 'on this computer',
  teamDetail: 'Every agent the team runs, cloud ones too, once an admin approves',
  folderDetail: (folder: string) => `Only agents in ${folder}`,
  computerDetail: 'Every agent, in every folder',
  action: 'Action',
  branches: 'Branches',
  paths: 'Paths',
  why: 'Why',
} as const;

/** The island while Memnox is not yet answering. */
export const IslandLines = {
  back: 'Back',
  working: (count: number) => (count === 1 ? '1 working' : `${count} working`),
  settings: 'Settings',
  tools: 'Tools',
  memnox: 'Memnox',
  checkAgain: 'Check again',
  waitingToStart: 'Waiting for Memnox to start',
  stopOrKeep: 'Stop or keep listening',
  mute: 'Mute the voice',
  unmute: 'Unmute the voice',
  agentsWorking: (count: number) => (count === 1 ? '1 agent working' : `${count} agents working`),
} as const;

/** The session cards on the island and the board. */
export const SessionCardLines = {
  seeChanging: 'See what it is changing',
  thinking: 'Thinking',
  nothingDone: 'Nothing done yet',
  goTo: 'Go to this session',
  open: 'Open this session',
  openIn: (where: string) => `Open this session in ${where}`,
  followUp: 'Follow-up',
  asked: 'Asked',
  youAsked: 'You asked',
  openLive: 'Open the live window to read the diffs',
  onlyNetwork: 'Memnox sees only where this session connects, not the files it changes',
  noFiles: 'No files changed yet',
  moreDiffs: (rest: number) => `${rest} more, see every diff`,
  seeDiffs: 'See the diffs',
  somewhereUnknown: 'Somewhere unknown',
  yourSessions: 'Your sessions',
} as const;

/** The live session window and the board. */
export const LiveSessionLines = {
  reading: 'Reading the session',
  openFolder: 'Open its folder',
  waiting: (count: number) => (count === 1 ? 'One call is waiting on you' : `${count} calls are waiting on you`),
  paused: (why: string) => `Paused: ${why}`,
  thinking: 'Thinking through its answer',
  nothingRecorded: 'Nothing recorded yet',
  nothingRecordedSentence: 'Nothing recorded yet.',
  noTranscript: 'This agent keeps no transcript Memnox can read, so its steps and changes tell the story.',
  noFiles: 'No files changed yet.',
  readingDiff: 'Reading the diff…',
  noDiff: 'No diff is known for this file.',
  conversation: 'Conversation',
  activity: 'Activity',
  about: 'About',
  whereItStands: 'Where it stands',
  noRequest: 'No request recorded for this session yet',
  latestAsk: (ask: string) => `Latest ask: ${ask}`,
} as const;

/** The side panel of questions asked and answered. */
export const SidePanelLines = {
  search: 'Search',
  clearSearch: 'Clear the search',
  unpin: 'Let it close when you click elsewhere',
  pin: 'Keep it open while you work',
  nothingMentions: (query: string) => `Nothing mentions “${query}”`,
  nothingAsked: 'Nothing asked yet',
  clearAll: 'Clear all?',
  clearHistory: 'Clear history',
  askAgain: 'Ask again',
} as const;

/** The launcher's tiles and the tools note under them. */
export const LauncherLines = {
  noApps: 'No apps connected yet. Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you.',
  noneYet: 'None yet',
  readingTools: 'Reading',
  connected: (count: number) => `${count} connected`,
  talkKey: 'Ctrl Alt Space',
  ruleKey: 'Hold Ctrl Alt',
} as const;

/** A question an agent asked, answered from the island. */
export const QuestionLines = {
  onScreen: 'Answer on screen',
  done: 'Done',
  tickWhatApplies: 'Tick what applies, then Done',
  pickOne: 'Pick one, or say your answer',
} as const;

/** The work card that sends words for the person: a mail, a message, a post. */
export const WorkCardLines = {
  close: 'Close without sending',
  asYou: 'As you',
  as: (who: string) => `As ${who}`,
  you: 'You',
  writeSomething: 'Write something to send',
  checkAddress: 'Check the address',
  send: 'Send with your fingerprint',
  sendWord: 'Send',
  to: 'To',
  addressExample: 'name@example.com',
  alsoSends: 'Also sends',
  changeAddress: 'Change who it goes to, then send it',
  address: 'The address it goes to',
  changeWords: 'Change the words, then send them',
  words: 'The words that will be sent',
  reply: 'Reply',
  newMessage: 'New Message',
  copy: 'Copy the message',
} as const;

/** The pill under the island after a sign in. */
export const SignedInLines = {
  notMe: 'Not me',
  signInAgain: 'Sign in again with your own account',
  signedIn: (toolkit: string, who: string | undefined) => (who === undefined ? `Signed in to ${toolkit}` : `Signed in to ${toolkit} as ${who}`),
} as const;

/** The floating cards over the desktop. */
export const FloatingLines = {
  watch: 'Watch live',
  back: 'Back',
  next: 'Next',
  open: 'Open',
  openSession: 'Open session',
  page: (at: number, count: number) => `Page ${at} of ${count}`,
} as const;

/** The spoken answer as the island shows it. */
export const ConversationLines = {
  memnox: 'Memnox',
  working: 'Working',
  thinking: 'Thinking',
  done: 'Done',
  copied: 'Copied',
  copy: 'Copy',
  openAnswer: 'Open answer',
  screenshot: 'Open the screenshot taken after it landed',
} as const;

/** The scan of the agents on this computer. */
export const ScanLines = {
  label: 'Scan of the agents on this computer',
  complete: 'Scan complete',
  scanning: 'Scanning this computer',
} as const;
