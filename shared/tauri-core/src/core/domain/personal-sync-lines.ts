import type { PersonalSyncConflict, PersonalSyncKindCount, PersonalSyncState } from '@memnox/core/wire';
import { counted } from './project-lines';

type Tone = 'good' | 'attention' | 'bad' | 'quiet';

/** Where personal sync stands, in a word beside its tone; the runtime's own sentence goes under it. */
const STATE_WORDS: Record<PersonalSyncState, { word: string; tone: Tone }> = {
  off: { word: 'Off', tone: 'quiet' },
  'waiting-for-key': { word: 'Waiting for the key', tone: 'attention' },
  'key-arrived': { word: 'Key arrived', tone: 'attention' },
  ready: { word: 'On', tone: 'good' },
  'not-on-plan': { word: 'Not on your plan', tone: 'quiet' },
  'no-person': { word: 'No person signed in', tone: 'quiet' },
};

export function syncStateWord(state: PersonalSyncState): { word: string; tone: Tone } {
  return STATE_WORDS[state];
}

/** What personal sync is, said above everything else on the page. */
export const SYNC_WHAT = 'Your own MCP servers, skills, projects, rules and the memory you confirmed, carried between your machines sealed under a key only they hold. It runs when you ask and after you change something here, never on a timer.';

/** Said beside a fingerprint on the machine giving the key. */
export const COMPARE_TO_OFFER = 'Compare these digits with the ones your other machine shows. Offer the key only if every group matches.';

/** Said beside a fingerprint on the machine taking the key. */
export const COMPARE_TO_ACCEPT = 'Compare these digits with the ones your machine holding the key shows. Accept only if every group matches.';

const KIND_TITLES: Record<string, { one: string; many: string }> = {
  servers: { one: 'MCP server', many: 'MCP servers' },
  skills: { one: 'skill', many: 'skills' },
  projects: { one: 'project', many: 'projects' },
  rules: { one: 'rule', many: 'rules' },
  memory: { one: 'memory fact', many: 'memory facts' },
};

/** "3 skills", "1 memory fact": a count of what this machine carries, never a score. */
export function kindCount(count: Pick<PersonalSyncKindCount, 'kind' | 'items'>): string {
  const title = KIND_TITLES[count.kind] ?? { one: count.kind, many: count.kind };
  return counted(count.items, title.one, title.many);
}

/** A kind on its own, for a conflict's caption: "Skill", "MCP server". */
export function kindTitle(kind: string): string {
  const title = KIND_TITLES[kind]?.one ?? kind;
  return `${title.charAt(0).toUpperCase()}${title.slice(1)}`;
}

/** The six groups of five digits the runtime writes, one each, so they read side by side. */
export function fingerprintGroups(fingerprint: string): string[] {
  const groups = fingerprint.trim().split(/\s+/).filter((group) => group !== '');
  if (groups.length > 1) return groups;
  const digits = groups[0] ?? '';
  return digits.match(/.{1,5}/g) ?? [];
}

/** "Last synced 5 min ago", or that it never has here. */
export function lastSyncedLine(when: string | undefined): string {
  return when === undefined ? 'Not synced on this machine yet.' : `Last synced ${when}.`;
}

/** "2 conflicts" waiting for a choice, or none. */
export function conflictsLine(count: number): string {
  if (count === 0) return 'No conflicts.';
  return `${counted(count, 'conflict', 'conflicts')} to choose between.`;
}

/** Who wrote the copy that lost and when it was kept, under its name. */
export function conflictCaption(conflict: Pick<PersonalSyncConflict, 'kind' | 'writtenBy'>, kept: string | undefined): string {
  const when = kept === undefined ? '' : `, kept ${kept}`;
  return `${kindTitle(conflict.kind)} written on ${conflict.writtenBy}${when}`;
}

/** Said under the opened copies: keeping one side sends it as the newest. */
export const CONFLICT_CHOICE = 'Keep theirs puts their copy back here and sends it as the newest. Keep mine lets their copy go.';

/** Said under Opened elsewhere: what the person opened on another machine and not here. */
export function openedElsewhereLine(count: number): string {
  return `${counted(count, 'repository', 'repositories')} opened on your other machines and not on this one.`;
}

/** Said once an offer or an accept was proposed: the key moves only once the person signs it. */
export function keyWaitsLine(keyTitle: string, offering: boolean): string {
  const what = offering ? 'Giving the key' : 'Taking the key';
  return `Nothing moves yet. ${what} waits for your signature with ${keyTitle} on the island.`;
}
