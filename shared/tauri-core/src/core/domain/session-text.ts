import type { CardFile, SessionCard, SessionView, SessionViewStep } from '@memnox/core/wire';
import { isActive, sessionStatus, statusLabel, type SessionStatus } from './session-status';

/**
 * How a session, its steps and its timings read on screen, ported from the Mac's `SessionText`,
 * `SessionReading` and `SessionDetailText`, kept as plain text so it is tested without a window.
 */

/** Sits between the parts of a subtitle, a middle dot with a space either side. */
export const SEPARATOR = ' · ';
/** Said in a subtitle while the agent is busy, in place of how long ago it last did anything. */
const WORKING_WORD = 'working';

/** Under this many seconds it is still the moment that just passed, not a minute ago. */
const JUST_NOW_SECONDS = 45;
const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
/** A folder and a file, which is how somebody names a file out loud. */
const SPOKEN_PATH_PARTS = 2;
/** Three folders above the file are enough to place it in a repository. */
const SHOWN_FOLDERS = 3;
/** The last two labels of a host name the site, so api.github.com reads as github.com. */
const SITE_LABELS = 2;
/** How the runtime starts a filesystem step that only read, which earns a page rather than a pencil. */
const READ_PREFIX = 'Read';
const MS_PER_SECOND = 1_000;

/** The Unicode private use areas, where terminal themes keep their icons, and the lost character mark. */
const UNREADABLE = /[-\u{F0000}-\u{FFFFD}\u{100000}-\u{10FFFD}�\p{Cc}]/gu;

/** The words with icon glyphs and control characters gone and their runs of space made one, or undefined when nothing is left. */
export function readable(text: string | undefined): string | undefined {
  if (text === undefined) return undefined;
  const words = text.replace(UNREADABLE, ' ').split(/\s+/).filter((word) => word !== '').join(' ');
  return words === '' ? undefined : words;
}

/** A repository name worth showing, since a folder named only by dots says nothing about where the work is. */
export function repositoryName(name: string | undefined): string | undefined {
  const kept = readable(name);
  if (kept === undefined || /^[./]+$/.test(kept)) return undefined;
  return kept;
}

/**
 * How long ago an ISO 8601 moment was, the way a person says it, or undefined when there is no readable
 * moment. A moment a little ahead of this clock is just now, since two machines rarely agree to the second.
 */
export function ago(iso: string | undefined, now: number): string | undefined {
  if (iso === undefined) return undefined;
  const at = Date.parse(iso);
  if (Number.isNaN(at)) return undefined;
  const seconds = Math.max(0, Math.floor((now - at) / MS_PER_SECOND));
  if (seconds < JUST_NOW_SECONDS) return 'just now';
  if (seconds < HOUR) return `${Math.max(1, Math.floor(seconds / MINUTE))} min ago`;
  if (seconds < DAY) return `${Math.floor(seconds / HOUR)} h ago`;
  return `${Math.floor(seconds / DAY)} d ago`;
}

/** The surfaces a step is drawn by, as the runtime's EVENT_SURFACE names them. */
const SURFACE = { filesystem: 'filesystem', shell: 'shell', git: 'git', network: 'network', mcp: 'mcp' } as const;

/** A step as a line: a host it called by its site's name, and anything else with each path cut to its last part. */
export function stepLine(step: SessionViewStep): string {
  const target = step.text.split(' ').pop();
  if (step.surface !== SURFACE.network || target === undefined) {
    // A full path says nothing a glance can use; its last part is the file or folder.
    return step.text
      .split(' ')
      .map((word) => (word.includes('/') ? (word.split('/').filter((part) => part !== '').pop() ?? word) : word))
      .join(' ');
  }
  const bare = target.replace(/^https?:\/\//, '');
  const host = bare.split('/')[0] ?? bare;
  const labels = host.split('.');
  const site = labels.length > SITE_LABELS ? labels.slice(-SITE_LABELS).join('.') : host;
  return `Reached ${site}`;
}

/**
 * The steps worth reading: what it changed and ran, leaving out the hosts it called unless that is all it
 * did, and one line, the latest, for the same thing done several times.
 */
export function meaningful(steps: readonly SessionViewStep[]): SessionViewStep[] {
  const work = steps.filter((step) => step.surface !== SURFACE.network);
  const kept: SessionViewStep[] = [];
  for (const step of work.length === 0 ? steps : work) {
    const line = stepLine(step);
    const at = kept.findIndex((each) => stepLine(each) === line);
    if (at >= 0) kept.splice(at, 1);
    kept.push(step);
  }
  return kept;
}

/** True when all Memnox saw of a session is where it connected, so an empty file list means unseen rather than unchanged. */
export function onlyNetwork(steps: readonly SessionViewStep[]): boolean {
  return steps.length > 0 && steps.every((step) => step.surface === SURFACE.network);
}

/** The SF Symbol a step is drawn with: what stopped it if something did, or else where it happened. */
export type StepSymbol = 'hand.raised' | 'xmark.circle' | 'doc.text' | 'pencil' | 'apple.terminal' | 'arrow.triangle.branch' | 'globe' | 'puzzlepiece' | 'circle';

export function stepSymbol(step: SessionViewStep): StepSymbol {
  if (step.refused === true) return 'hand.raised';
  if (step.failed === true) return 'xmark.circle';
  switch (step.surface) {
    case SURFACE.filesystem:
      return step.text.startsWith(READ_PREFIX) ? 'doc.text' : 'pencil';
    case SURFACE.shell:
      return 'apple.terminal';
    case SURFACE.git:
      return 'arrow.triangle.branch';
    case SURFACE.network:
      return 'globe';
    case SURFACE.mcp:
      return 'puzzlepiece';
    default:
      return 'circle';
  }
}

/** A refused step in amber, a failed one in red, the current one white and the rest quiet. */
export function stepTint(step: SessionViewStep, current: boolean): string {
  if (step.refused === true) return '#FF9F0A';
  if (step.failed === true) return '#FF453A';
  return current ? '#FFFFFF' : '#5F646D';
}

/** The last two parts of a path, which is how somebody names a file out loud. */
export function shortPath(path: string): string {
  return path.split('/').filter((part) => part !== '').slice(-SPOKEN_PATH_PARTS).join('/');
}

/** A file's own name, the last part of its path. */
export function fileName(path: string): string {
  return path.split('/').filter((part) => part !== '').pop() ?? path;
}

/** The folders a file sits in, the last few only, since the file's own name is already beside it. */
export function folderOf(path: string): string {
  return path.split('/').filter((part) => part !== '').slice(0, -1).slice(-SHOWN_FOLDERS).join('/');
}

/** The counts of the file an excerpt is from, when the session's file list has it. */
export function countsFor(path: string, files: readonly CardFile[]): CardFile | undefined {
  return files.find((file) => file.path === path) ?? files.find((file) => path.endsWith(file.path) || file.path.endsWith(path));
}

/** Every line added and removed across the files, for the totals over a file list. */
export function totals(files: readonly CardFile[]): { added: number; removed: number } {
  return files.reduce((sum, file) => ({ added: sum.added + (file.added ?? 0), removed: sum.removed + (file.removed ?? 0) }), { added: 0, removed: 0 });
}

/** The trace's own step names, as a person would say them. */
const TRACE_NAMES: Record<string, string> = {
  'voice.turn': 'Your question',
  'voice.context': 'Reading the sessions',
  'brain.turn': 'Thinking',
  'mac.waiting for the end': 'Waiting for you to finish',
  'mac.first sentence ready': 'Answer arriving',
  'mac.speaking': 'Speaking',
};

/** A trace step as a person would name it, rather than the name it was recorded under. */
export function traceStepName(name: string): string {
  const said = TRACE_NAMES[name];
  if (said !== undefined) return said;
  if (name.startsWith('brain.')) return `Asked ${name.slice('brain.'.length)}`;
  if (name.startsWith('operator.')) return `Ran ${name.slice('operator.'.length)}`;
  return name;
}

/** Milliseconds under a second and seconds with one place above, the way a waterfall is read. */
export function duration(milliseconds: number): string {
  return milliseconds < MS_PER_SECOND ? `${Math.trunc(milliseconds)} ms` : `${(milliseconds / MS_PER_SECOND).toFixed(1)} s`;
}

/** A card's status from its own facts; the list never says how many calls wait, so only a view can say needs you. */
export function cardStatus(card: SessionCard): SessionStatus {
  return sessionStatus({ state: card.state, thinking: card.thinking });
}

export function viewStatus(view: SessionView): SessionStatus {
  return sessionStatus({ state: view.state, thinking: view.thinking, paused: view.paused, waitingOnYou: view.waitingOnYou });
}

/** What a session is on, which is what tells two sessions of the same agent apart, with terminal glyphs taken out. */
export function cardTitle(card: Pick<SessionCard, 'task' | 'repository' | 'agentName'>): string {
  return readable(card.task) ?? repositoryName(card.repository) ?? card.agentName;
}

/** The agent, where it is if the title did not say, and how lately it did anything. */
export function cardSubtitle(card: SessionCard, now: number): string {
  const title = cardTitle(card);
  const parts: string[] = [];
  if (title !== card.agentName) parts.push(card.agentName);
  const repository = repositoryName(card.repository);
  if (repository !== undefined && repository !== title) parts.push(repository);
  parts.push(isActive(cardStatus(card)) ? WORKING_WORD : (ago(card.lastActive, now) ?? card.state));
  return parts.join(SEPARATOR);
}

/** Its repository and the branch there, the way a person names where the work happens. */
export function viewPlace(view: SessionView): string | undefined {
  if (view.repository === undefined) return view.runningIn;
  return view.branch === undefined ? view.repository : `${view.repository} on ${view.branch}`;
}

/** Where it runs, when it began and how lately it did anything, the quiet line under what it is about. */
export function viewContext(view: SessionView, now: number): string | undefined {
  const started = ago(view.startedAt, now);
  const active = ago(view.lastActive, now);
  const parts = [
    view.where ?? view.runningIn,
    started === undefined ? undefined : `started ${started}`,
    isActive(viewStatus(view)) ? WORKING_WORD : active === undefined ? undefined : `active ${active}`,
  ].filter((part): part is string => part !== undefined);
  return parts.length === 0 ? undefined : parts.join(SEPARATOR);
}

/** The badge's words, with how long it has been quiet when that is all there is to say. */
export function badgeLabel(view: SessionView, now: number): string {
  const status = viewStatus(view);
  const since = ago(view.lastActive, now);
  if (status !== 'quiet' || since === undefined) return statusLabel(status);
  return `Quiet, ${since}`;
}

/** The repository and the app it runs in, which is what tells two sessions of one agent apart. */
export function detailPlace(view: SessionView): string | undefined {
  const parts = [repositoryName(view.repository), view.runningIn].filter((part): part is string => part !== undefined && part !== '');
  return parts.length === 0 ? undefined : parts.join(SEPARATOR);
}

/** The person's latest ask when it differs from the task, else the task: what a card says it is on. */
export function currentAsk(view: Pick<SessionView, 'task' | 'lastAsk'>): { words: string; followUp: boolean } | undefined {
  const opening = readable(view.task);
  const latest = readable(view.lastAsk);
  const followUp = latest !== undefined && latest !== opening;
  const words = followUp ? latest : opening;
  return words === undefined ? undefined : { words, followUp };
}

/** A changed line as a diff marks it, with the indent every line shares taken off. */
export interface ExcerptLine {
  readonly added: boolean;
  readonly text: string;
}

/**
 * The changed lines with the marker split off and the shared indent removed, so deeply nested code still
 * starts at the left edge rather than half way across a narrow panel.
 */
export function excerptLines(lines: readonly string[]): ExcerptLine[] {
  const split = lines.map((line) => ({ added: !line.startsWith('-'), text: line.startsWith('+') || line.startsWith('-') ? line.slice(1) : line }));
  const indent = (text: string) => text.length - text.replace(/^[ \t]+/, '').length;
  const indents = split.map((line) => line.text).filter((text) => text.trim() !== '').map(indent);
  const shared = indents.length === 0 ? 0 : Math.min(...indents);
  return split.map((line) => ({ added: line.added, text: line.text.slice(Math.min(shared, indent(line.text))) }));
}

/** One line of a file's diff as the live window draws it, numbered on the side it belongs to. */
export interface DiffLine {
  readonly kind: 'hunk' | 'added' | 'removed' | 'context';
  readonly text: string;
  readonly old?: number;
  readonly new?: number;
}

/** Where each side of a hunk starts, from its header such as `@@ -12,7 +12,9 @@`. */
function hunkStarts(header: string): { old: number; new: number } {
  const match = /@@ -(\d+)(?:,\d+)? \+(\d+)/.exec(header);
  return { old: Number(match?.[1] ?? 0), new: Number(match?.[2] ?? 0) };
}

/** A unified diff's hunks as numbered lines; header lines before the first hunk are left out. */
export function diffLines(lines: readonly string[]): DiffLine[] {
  let old = 0;
  let added = 0;
  const parsed: DiffLine[] = [];
  for (const line of lines) {
    if (line.startsWith('@@')) {
      ({ old, new: added } = hunkStarts(line));
      parsed.push({ kind: 'hunk', text: line.split('@@').slice(2).join('@@').trim() });
    } else if (parsed.length === 0 || line.startsWith('\\')) {
      continue;
    } else if (line.startsWith('+')) {
      parsed.push({ kind: 'added', text: line.slice(1), new: added });
      added += 1;
    } else if (line.startsWith('-')) {
      parsed.push({ kind: 'removed', text: line.slice(1), old });
      old += 1;
    } else {
      parsed.push({ kind: 'context', text: line.slice(1), old, new: added });
      old += 1;
      added += 1;
    }
  }
  return parsed;
}
