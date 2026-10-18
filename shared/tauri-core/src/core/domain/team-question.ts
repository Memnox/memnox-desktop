import { HELD_ASK, withShortPaths } from './spoken';
import { callWhat, callWho, callWhy, type WorkspaceHeldCall } from './workspace-wire';

const SENTENCE_ENDS = '.!?';

function ended(text: string): string {
  const trimmed = text.trim();
  const last = trimmed[trimmed.length - 1];
  return last === undefined || SENTENCE_ENDS.includes(last) ? trimmed : `${trimmed}.`;
}

/**
 * A teammate's call the workspace routed here, said the way a call on this computer is: who and where, what it
 * wants and why, ending on the same question so the answer can be spoken or pressed. Ported from the Mac's `teamQuestion`.
 */
export function teamQuestion(owner: string | undefined, call: WorkspaceHeldCall): string {
  let question = `${callWho(call)} is waiting on you.`;
  if (owner !== undefined && owner !== '') question = `${owner}, ${question}`;
  question += ` ${ended(withShortPaths(callWhat(call)))}`;
  const why = callWhy(call);
  if (why !== '') question += ` ${ended(withShortPaths(why))}`;
  return `${question} ${HELD_ASK}`;
}
