import type { DaemonEvent } from '@memnox/core/wire';
import { LINES } from './spoken';

/** Each kind of change a proposal carries, by the runtime's PROPOSAL_KIND value, said as what saying yes would do. */
export const PROPOSAL_PHRASES: Readonly<Record<string, string>> = {
  rules: 'a new rule',
  answer: 'an answer to a held call',
  resume: 'letting a paused session carry on',
  rewind: 'putting a repository back to a milestone',
  command: 'running a Memnox command',
  mac: 'something only this computer can do',
  team: 'an answer to your team',
  work: 'acting in one of your own accounts',
  account: 'claiming an account as your own',
  'mcp-hub': 'a change to your MCP servers',
  'rule-remove': 'removing one of your rules',
  'agent-resume': 'letting a paused agent carry on',
  'skills-hub': 'a change to your skills',
  project: 'handing a project its setup',
  'backup-restore': 'putting a backup back',
  lan: 'opening this computer to your local network',
  'personal-sync-key': 'sharing your personal sync key',
  'index-source': 'reading listings from another source',
};

type Proposed = Pick<DaemonEvent, 'proposalKind' | 'summary'>;

/** The phrase for a kind the daemon named; an older daemon names none, and a newer one may name one not known here. */
function phraseOf(event: Proposed): string | undefined {
  return event.proposalKind === undefined ? undefined : PROPOSAL_PHRASES[event.proposalKind];
}

/** What the key's prompt says it is for: the kind first where one is known, then the proposal's own words. */
export function proposalPrompt(event: Proposed): string {
  const phrase = phraseOf(event);
  if (phrase === undefined) return event.summary;
  return `${phrase.charAt(0).toUpperCase()}${phrase.slice(1)}: ${event.summary}`;
}

/** Said once a proposal nobody asked for is declined, naming what it would have done where the kind is known. */
export function unaskedLine(event: Proposed): string {
  const phrase = phraseOf(event);
  return phrase === undefined ? LINES.unasked : `Something proposed ${phrase}, which you did not ask for. I have declined it.`;
}
