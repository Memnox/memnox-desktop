import { PROPOSAL_ANSWER, type DaemonEvent, type ProposalAnswer } from '@memnox/core/wire';

/** Long enough to say what the agent is on, short enough that the question still comes quickly. */
const TASK_CAPTION_LIMIT = 70;
const SENTENCE_ENDS = '.!?';
/** Two parts at least, since "/src" alone is already as short as it gets. */
const LEAST_PATH_PARTS = 2;
const TRAILING_MARKS = /[.,;:?!)]+$/;
const MCP_TOOL_SEPARATOR = '__';

/** What every spoken held call ends on, so the answer can be said or pressed. */
export const HELD_ASK = 'Allow it, or deny?';

/** Text cut at a word to fit a caption, on one line. */
export function caption(text: string, limit: number): string {
  const flat = text.split(/\r?\n/).join(' ');
  if (flat.length <= limit) return flat;
  const cut = flat.slice(0, limit);
  const space = cut.lastIndexOf(' ');
  return `${space === -1 ? cut : cut.slice(0, space)}…`;
}

/** `mcp__memnox-operator__sessions` as a person would read it. */
export function toolWord(tool: string | undefined): string {
  if (tool === undefined) return 'the machine';
  return tool.split(MCP_TOOL_SEPARATOR).pop() ?? tool;
}

/** Every path said by its last part, since a full path read aloud is noise. */
export function withShortPaths(sentence: string): string {
  return sentence
    .split(' ')
    .map((word) => {
      const body = word.replace(TRAILING_MARKS, '');
      const isPath = (body.startsWith('/') || body.startsWith('~/')) && body.split('/').filter(Boolean).length >= LEAST_PATH_PARTS;
      const last = body.split('/').filter(Boolean).pop();
      return isPath && last !== undefined ? last + word.slice(body.length) : word;
    })
    .join(' ');
}

function ended(text: string): string {
  const trimmed = text.trim();
  const last = trimmed[trimmed.length - 1];
  return last === undefined || SENTENCE_ENDS.includes(last) ? trimmed : `${trimmed}.`;
}

/** A held call said out loud when the brain could not tell it: who, where, on what, what it wants and why. */
export function heldQuestion(owner: string | undefined, event: DaemonEvent, label: string): string {
  let sentence: string;
  if (event.what !== undefined && event.what !== '') {
    sentence = label;
    if (event.place !== undefined && event.place !== '') sentence += ` in ${event.place}`;
    // A follow up is what the call answers to, so it is said over the mission it belongs to.
    if (event.lastAsk !== undefined && event.lastAsk !== '') sentence += `, after you said ${caption(event.lastAsk, TASK_CAPTION_LIMIT)},`;
    else if (event.task !== undefined && event.task !== '') sentence += `, working on ${caption(event.task, TASK_CAPTION_LIMIT)},`;
    sentence += ` wants to ${withShortPaths(event.what)}`;
  } else {
    // An older daemon sends only the summary, which already says who wants what.
    sentence = withShortPaths(event.summary);
  }
  if (owner !== undefined && owner !== '') sentence = `${owner}, ${sentence}`;
  let question = ended(sentence);
  if (event.why !== undefined && event.why !== '') question += ` ${ended(withShortPaths(event.why))}`;
  return `${question} ${HELD_ASK}`;
}

/** The runtime's outcomes for a confirmed command still running on its own, and a held call let through. */
const CONFIRM_STARTED = 'started';
const CONFIRM_LET_THROUGH = 'let-through';

/** A command still running on its own, or a held call only let through, is never called done. */
export function afterConfirm(answer: ProposalAnswer, outcome: string | undefined): string {
  if (answer !== PROPOSAL_ANSWER.CONFIRMED) return 'Very well. I have left it as it was.';
  if (outcome === CONFIRM_STARTED) return 'Very well. It is under way, and I will tell you if anything goes wrong.';
  if (outcome === CONFIRM_LET_THROUGH) return 'Very well. I have let it through, and it carries on from here.';
  return 'Very well. It is done.';
}

export const LINES = {
  unasked: 'Something proposed an allow you did not ask for. I have declined it.',
  unreachable: 'My apologies, I cannot reach Memnox on this computer at the moment.',
  tooOld: 'The Memnox running on this computer is older than this app, so it cannot answer yet. Update Memnox and ask me again.',
  stalled: 'My apologies, I lost the thread there. Could you say that again?',
  limited: 'Your plan has reached its limit, so I could not finish that.',
  /** A rule or a message to send needs its card, which this app does not draw yet. */
  needsCard: 'That one needs its card, which I cannot show here yet, so answer it on your phone or in the terminal.',
} as const;
