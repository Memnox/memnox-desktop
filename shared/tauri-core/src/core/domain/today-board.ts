import { AGENT_STATUS, HOLD_ANSWER, type ActivityRow, type AgentView, type HomeReady, type ProjectView, type SessionCard } from '@memnox/core/wire';
import { inLine, projectName, projectNameOfPlace } from './project-context';
import { FROM_NOW_ON, type HeldAnswer } from './call-label';
import { HomeLines } from './home-lines';
import { cardStatus, cardTitle, readable, repositoryName, SEPARATOR } from './session-text';
import { activityWords } from './activity-words';
import { activityLine, answeredWords, EFFECT_WORDS, isEffect } from './studio-lines';
import { ALWAYS_ALLOW, ANSWER_LABEL } from './answer-words';

/**
 * Today, ported from the Mac's `TodayBoard` and `TodayLines`: what needs the person, most urgent first, read off what
 * the window already holds. It decides nothing; every answer to a held call goes back through `HeldCalls`, which signs
 * an allow exactly as the island does.
 */

/** Where an item on Today stands, as its pill says it. */
export type TodayState = 'needs-you' | 'stopped' | 'working' | 'up-next' | 'done';

export const TODAY_STATE_LABEL: Record<TodayState, string> = {
  'needs-you': 'Needs you',
  stopped: 'Stopped',
  working: 'Working',
  'up-next': 'Up next',
  done: 'Done',
};

/** The Overview's sections, in the order they are read. */
export type TodaySection = 'needs-you' | 'next' | 'working';

export const TODAY_SECTIONS: readonly TodaySection[] = ['needs-you', 'next', 'working'];

/** The tabs across Today. */
export type TodayTab = 'overview' | 'done' | 'handoffs' | 'log';

/** What an item came from, which decides how urgent it is and what can be done about it. */
export type TodayKind =
  /** A held call, its agent stopped until somebody answers. `team` for one the workspace routed from a teammate. */
  | { readonly kind: 'held'; readonly team: boolean }
  | { readonly kind: 'refused'; readonly count: number }
  | { readonly kind: 'failed'; readonly exit: number; readonly count: number }
  | { readonly kind: 'paused' }
  | { readonly kind: 'handed-back' }
  /** A step only the person can take, word for word as the runtime says it. */
  | { readonly kind: 'owed' }
  /** An agent found here that runs outside Memnox. */
  | { readonly kind: 'unprotected' }
  /** The one action said yes to often enough, and never refused, to run on its own. */
  | { readonly kind: 'hand-over' }
  | { readonly kind: 'working' }
  | { readonly kind: 'done' };

/** What a choice in the panel does. */
export type TodayAction =
  | { readonly kind: 'answer'; readonly answer: HeldAnswer }
  | { readonly kind: 'hand-over' }
  | { readonly kind: 'protect' }
  | { readonly kind: 'open-conversation' }
  | { readonly kind: 'find-in-app' }
  | { readonly kind: 'open-activity' };

/** One choice in the panel, pressed by its letter. */
export interface TodayChoice {
  readonly key: string;
  readonly title: string;
  readonly action: TodayAction;
  /** Marked only where the runtime or the agent recommended it; this app never picks one itself. */
  readonly recommended: boolean;
}

/** One line of Today: what it is, who it is from, since when, and where it stands. */
export interface TodayItem {
  readonly id: string;
  readonly kind: TodayKind;
  readonly title: string;
  /** One muted line under the title: why it asks, where it runs, or what the rule said. */
  readonly detail?: string;
  /** What the runtime or the agent recommends, word for word; absent where neither said anything. */
  readonly recommendation?: string;
  readonly agent?: string;
  readonly agentName: string;
  /** Milliseconds since the epoch. */
  readonly since?: number;
  readonly sessionId?: string;
  readonly state: TodayState;
  readonly choices: readonly TodayChoice[];
  /** The project it happens in, by its name, so a person with several projects sees where; absent where nothing says. */
  readonly project?: string;
}

/** Lower is more urgent: what blocks an agent first, then what stopped, then what waits, then what is next. */
export function urgency(item: Pick<TodayItem, 'kind'>): number {
  switch (item.kind.kind) {
    case 'held':
    case 'refused':
      return 0;
    case 'failed':
    case 'paused':
      return 1;
    case 'handed-back':
      return 2;
    case 'owed':
      return 3;
    case 'unprotected':
      return 4;
    case 'hand-over':
      return 5;
    case 'working':
      return 6;
    case 'done':
      return 7;
  }
}

/** The Overview section an item sits in; undefined for what is only in the record. */
export function sectionOf(item: Pick<TodayItem, 'kind'>): TodaySection | undefined {
  switch (item.kind.kind) {
    case 'held':
    case 'refused':
    case 'failed':
    case 'paused':
    case 'handed-back':
      return 'needs-you';
    case 'owed':
    case 'unprotected':
    case 'hand-over':
      return 'next';
    case 'working':
      return 'working';
    case 'done':
      return undefined;
  }
}

/** A held call as Today reads it off the queue, so the board never sees the island's own card. */
export interface TodayHeld {
  readonly subject: string;
  readonly agent: string;
  readonly who: string;
  readonly what: string;
  readonly why?: string;
  /** When it started waiting, as the runtime wrote it. */
  readonly at?: string;
  readonly team?: boolean;
  readonly sessionId?: string;
  /** The folder it waits in, by name, as the daemon's event names it. */
  readonly place?: string;
}

/** Everything Today is read from, each already held by the window. */
export interface TodaySources {
  readonly held: readonly TodayHeld[];
  readonly sessions: readonly SessionCard[];
  readonly activity: readonly ActivityRow[];
  readonly agents: readonly AgentView[];
  /** What only the person can do, word for word as the home says it. */
  readonly owed: readonly string[];
  readonly ready?: HomeReady;
  /** The projects on this computer, which name where a held call or a session happens. */
  readonly projects?: readonly ProjectView[];
}

/** How many of what needs the person the Overview shows before it folds the rest behind a press. */
export const URGENT_SHOWN = 5;

/** Local midnight of the day `now` falls in. */
export function startOfDay(now: number): number {
  const day = new Date(now);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

/** Reads a moment the runtime wrote, with or without fractional seconds. */
export function moment(iso: string | undefined): number | undefined {
  if (iso === undefined) return undefined;
  const at = Date.parse(iso);
  return Number.isNaN(at) ? undefined : at;
}

/** Everything on the Overview, most urgent first and the oldest first within the same urgency. */
export function overview(sources: TodaySources, now: number): TodayItem[] {
  const today = ofToday(sources.activity, now);
  return ordered([...heldItems(sources.held, sources.projects ?? []), ...stopped(today), ...sessionItems(sources.sessions, sources.projects ?? []), ...next(sources)]);
}

/** The urgency rule: what blocks an agent first, then age, oldest first, an item with no age after those with one. */
export function ordered(items: readonly TodayItem[]): TodayItem[] {
  return items
    .map((item, offset) => ({ item, offset }))
    .sort((left, right) => {
      const a = left.item;
      const b = right.item;
      if (urgency(a) !== urgency(b)) return urgency(a) - urgency(b);
      if (a.since !== undefined && b.since !== undefined && a.since !== b.since) return a.since - b.since;
      if (a.since !== undefined && b.since === undefined) return -1;
      if (a.since === undefined && b.since !== undefined) return 1;
      return left.offset - right.offset;
    })
    .map((each) => each.item);
}

/** The Overview's items under their sections, an empty section dropped. */
export function sections(items: readonly TodayItem[]): { section: TodaySection; items: TodayItem[] }[] {
  return TODAY_SECTIONS.flatMap((section) => {
    const held = items.filter((item) => sectionOf(item) === section);
    return held.length === 0 ? [] : [{ section, items: held }];
  });
}

/** What went through today and ran, newest first. */
export function done(activity: readonly ActivityRow[], now: number): TodayItem[] {
  return newestFirst(ofToday(activity, now).filter((row) => row.effect === 'allow' && row.failed === undefined)).map((row) => record(row, 'done'));
}

/** What agents handed back to the person, and what the runtime offers to let run on its own. */
export function handoffs(sources: TodaySources): TodayItem[] {
  return ordered([...sessionItems(sources.sessions, sources.projects ?? []).filter((item) => item.kind.kind === 'handed-back'), ...(sources.ready === undefined ? [] : [handOver(sources.ready)])]);
}

/** Every action today, newest first, each with what came of it. */
export function log(activity: readonly ActivityRow[], now: number): TodayItem[] {
  return newestFirst(ofToday(activity, now)).map((row) => {
    let state: TodayState;
    if (row.failed !== undefined) state = 'stopped';
    else if (row.effect === 'deny') state = 'stopped';
    else if (row.effect === 'ask') state = row.answeredBy === undefined ? 'needs-you' : 'done';
    else state = 'done';
    return record(row, state);
  });
}

/** The item `offset` places from the one open, stopping at either end; the first when none is open. */
export function step(from: string | undefined, offset: number, items: readonly TodayItem[]): string | undefined {
  if (items.length === 0) return undefined;
  const at = from === undefined ? -1 : items.findIndex((item) => item.id === from);
  if (at < 0) return items[0]?.id;
  return items[Math.min(Math.max(at + offset, 0), items.length - 1)]?.id;
}

/** The choice a letter presses, in either case. */
export function choiceFor(key: string, item: TodayItem): TodayChoice | undefined {
  const pressed = key.toUpperCase();
  return item.choices.find((choice) => choice.key === pressed);
}

/**
 * The answers a held call takes, in the words and order every surface uses, Deny last. A teammate's call has no rule
 * here to relax, so Always allow is left off it, since the runtime would take it as once.
 */
export function heldChoices(team: boolean): TodayChoice[] {
  const answers: [string, HeldAnswer][] = [
    [ANSWER_LABEL[HOLD_ANSWER.ONCE], HOLD_ANSWER.ONCE],
    [ANSWER_LABEL[HOLD_ANSWER.SESSION], HOLD_ANSWER.SESSION],
  ];
  if (!team) answers.push([ALWAYS_ALLOW, FROM_NOW_ON]);
  answers.push([ANSWER_LABEL[HOLD_ANSWER.DENY], HOLD_ANSWER.DENY]);
  return lettered(answers.map(([title, answer]) => [title, { kind: 'answer', answer }, false]));
}

/** Whether an allow pressed here is signed: every one is, unless the daemon placed the call inside its session. */
export function signs(choice: TodayChoice, touchID: boolean | undefined): boolean {
  if (choice.action.kind !== 'answer' || choice.action.answer === HOLD_ANSWER.DENY) return false;
  return touchID ?? true;
}

function heldItems(calls: readonly TodayHeld[], projects: readonly ProjectView[]): TodayItem[] {
  return calls.map((call) => ({
    id: heldId(call.subject),
    kind: { kind: 'held', team: call.team === true },
    title: call.what,
    ...(call.why === undefined ? {} : { detail: call.why }),
    agent: call.agent,
    agentName: call.who,
    ...optional('since', moment(call.at)),
    ...optional('sessionId', call.sessionId),
    state: 'needs-you',
    choices: heldChoices(call.team === true),
    ...optional('project', projectNameOfPlace(call.place, projects)),
  }));
}

/** The id a held call's item goes by, so the panel finds its card again. */
export function heldId(subject: string): string {
  return `held:${subject}`;
}

/** Refusals and failures, the same action by the same agent folded into one line with its count. */
function stopped(rows: readonly ActivityRow[]): TodayItem[] {
  const groups: { key: string; rows: ActivityRow[] }[] = [];
  for (const row of rows) {
    if (row.effect !== 'deny' && row.failed === undefined) continue;
    const key = [row.effect === 'deny' ? 'refused' : 'failed', row.agent, row.operation, row.target ?? ''].join('\u0000');
    const known = groups.find((group) => group.key === key);
    if (known === undefined) groups.push({ key, rows: [row] });
    else known.rows.push(row);
  }
  return groups.flatMap((group) => {
    const latest = newestFirst(group.rows)[0];
    if (latest === undefined) return [];
    const refused = latest.effect === 'deny';
    const count = group.rows.length;
    const kind: TodayKind = refused ? { kind: 'refused', count } : { kind: 'failed', exit: latest.failed ?? 0, count };
    const reason = refused ? (latest.rule === undefined ? latest.reason : `Refused by ${latest.rule}`) : `Failed, exit ${latest.failed ?? 0}`;
    const times = count > 1 ? `${reason}, ${count} times today` : reason;
    return [
      {
        id: `stopped:${latest.id}`,
        kind,
        title: activityLine(latest),
        detail: times,
        agent: latest.agent,
        agentName: latest.agentName,
        ...optional('since', moment(latest.at)),
        sessionId: latest.session,
        state: 'stopped' as const,
        choices: lettered([['See why in Activity', { kind: 'open-activity' }, false]]),
      },
    ];
  });
}

function sessionItems(cards: readonly SessionCard[], projects: readonly ProjectView[]): TodayItem[] {
  return cards.flatMap((card) => {
    let kind: TodayKind;
    let state: TodayState;
    switch (cardStatus(card)) {
      case 'stopped':
        kind = { kind: 'paused' };
        state = 'stopped';
        break;
      case 'finished':
      case 'needs-you':
        kind = { kind: 'handed-back' };
        state = 'needs-you';
        break;
      case 'working':
        kind = { kind: 'working' };
        state = 'working';
        break;
      case 'idle':
        return [];
    }
    const ways: [string, TodayAction, boolean][] = [['Open conversation', { kind: 'open-conversation' }, false]];
    if (card.host?.app !== undefined) ways.push(['Find in app', { kind: 'find-in-app' }, false]);
    const project = projectName(card.repository, projects);
    // The project names where it runs, so the detail says only what the place alone does not.
    const detail = kind.kind === 'paused' ? 'Paused, so nothing it asks for runs' : project === undefined ? repositoryName(card.repository) : undefined;
    return [
      {
        id: `session:${card.sessionId}`,
        kind,
        title: cardTitle(card),
        ...optional('detail', detail),
        agent: card.agent,
        agentName: card.agentName,
        ...optional('since', moment(card.lastActive)),
        sessionId: card.sessionId,
        state,
        choices: lettered(ways),
        ...optional('project', project),
      },
    ];
  });
}

function next(sources: TodaySources): TodayItem[] {
  const owed = sources.owed.flatMap((line) => {
    const words = readable(line);
    return words === undefined ? [] : [{ id: `owed:${words}`, kind: { kind: 'owed' } as const, title: words, detail: 'Only you can do this', agentName: 'Memnox', state: 'up-next' as const, choices: [] }];
  });
  const outside = sources.agents
    .filter((agent) => agent.status === AGENT_STATUS.UNPROTECTED)
    .map(
      (agent): TodayItem => ({
        id: `unprotected:${agent.kind}`,
        kind: { kind: 'unprotected' },
        title: `Put ${agent.name} under Memnox`,
        detail: 'It runs outside Memnox, so nothing it does is ruled on',
        agent: agent.kind,
        agentName: agent.name,
        state: 'up-next',
        choices: lettered([['Protect it', { kind: 'protect' }, false]]),
      }),
    );
  return [...owed, ...outside, ...(sources.ready === undefined ? [] : [handOver(sources.ready)])];
}

/** The runtime's own suggestion, so its because is a recommendation and Hand over the choice it recommends. */
function handOver(ready: HomeReady): TodayItem {
  return {
    id: `ready:${ready.action}`,
    kind: { kind: 'hand-over' },
    title: HomeLines.ready(ready),
    recommendation: ready.because,
    agentName: ready.agentName ?? 'Memnox',
    state: 'up-next',
    choices: lettered([['Hand it over', { kind: 'hand-over' }, true]]),
  };
}

function record(row: ActivityRow, state: TodayState): TodayItem {
  const verdict = isEffect(row.effect) ? EFFECT_WORDS[row.effect].verdict : row.effect;
  const detail = [verdict, row.rule, answeredWords(row)].filter((part): part is string => part !== undefined).join(SEPARATOR);
  return {
    id: `row:${row.id}`,
    kind: { kind: 'done' },
    title: activityWords(row),
    detail,
    agent: row.agent,
    agentName: row.agentName,
    ...optional('since', moment(row.at)),
    sessionId: row.session,
    state,
    choices: lettered([['See why in Activity', { kind: 'open-activity' }, false]]),
  };
}

const LETTERS = 'ABCDEFGHIJ';

function lettered(choices: readonly (readonly [string, TodayAction, boolean])[]): TodayChoice[] {
  return choices.slice(0, LETTERS.length).map(([title, action, recommended], at) => ({ key: LETTERS[at] ?? '', title, action, recommended }));
}

/** Rows since local midnight, since a page of the ledger may reach further back. */
export function ofToday(rows: readonly ActivityRow[], now: number): ActivityRow[] {
  const start = startOfDay(now);
  return rows.filter((row) => (moment(row.at) ?? -Infinity) >= start);
}

function newestFirst(rows: readonly ActivityRow[]): ActivityRow[] {
  return [...rows].sort((a, b) => (moment(b.at) ?? -Infinity) - (moment(a.at) ?? -Infinity));
}

/** A field only where it has a value, since the items are compared whole and an undefined key would differ. */
function optional<K extends string, V>(key: K, value: V | undefined): { [P in K]?: V } {
  return (value === undefined ? {} : { [key]: value }) as { [P in K]?: V };
}

// The words around Today's table: the line under its title, the strip over it, and the panel's own.

/** What the panel says where neither the runtime nor the agent recommended anything, rather than guessing one. */
export const NO_RECOMMENDATION = 'Neither the runtime nor the agent recommended anything for this, so the choice is yours.';
export const NO_CHOICES = 'There is nothing to decide here; it is shown so you know it is there.';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const SECOND = 1_000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
/** Under this long an age reads as now, since the reads behind it are a few seconds apart. */
const NOW_MS = 10 * SECOND;

/** "1 Nov. 13 need you, 1 next, 7 open projects", each count from what the window holds. */
export function headline(now: number, needYou: number, nextCount: number, openProjects: number): string {
  const parts = [needYou === 0 ? 'nothing needs you' : `${needYou} ${needYou === 1 ? 'needs' : 'need'} you`, `${nextCount} next`, `${openProjects} open ${openProjects === 1 ? 'project' : 'projects'}`];
  return `${dayLine(now)} ${parts.join(', ')}`;
}

/** The day as "1 Nov.", in English month words, as every other line here is. */
export function dayLine(now: number): string {
  const date = new Date(now);
  return `${date.getDate()} ${MONTHS[date.getMonth()] ?? ''}.`;
}

/** "13 need you, the 5 most urgent here", or how many need you when every one is shown. */
export function stripLine(needYou: number, shown: number): string {
  if (needYou <= 0) return 'Nothing needs you';
  const lead = `${needYou} ${needYou === 1 ? 'needs' : 'need'} you`;
  return shown < needYou ? `${lead}, the ${shown} most urgent here` : lead;
}

/** What waits, by kind: "4 held calls, 2 stopped, 1 handed back". */
export function waitsLine(items: readonly TodayItem[]): string | undefined {
  const held = items.filter((item) => item.kind.kind === 'held').length;
  const stoppedCount = items.filter((item) => item.state === 'stopped').length;
  const back = items.filter((item) => item.kind.kind === 'handed-back').length;
  const parts = [held > 0 ? `${held} held ${held === 1 ? 'call' : 'calls'}` : undefined, stoppedCount > 0 ? `${stoppedCount} stopped` : undefined, back > 0 ? `${back} handed back` : undefined].filter(
    (part): part is string => part !== undefined,
  );
  return parts.length === 0 ? undefined : parts.join(', ');
}

/** "synced 13:14", the last time the window read what it shows. */
export function syncedLine(at: number): string {
  const date = new Date(at);
  return `synced ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

/** How long ago, short enough for a column: "now", "12 s", "4 min", "2 h", "3 d". */
export function age(since: number | undefined, now: number): string | undefined {
  if (since === undefined) return undefined;
  const elapsed = Math.max(0, now - since);
  if (elapsed < NOW_MS) return 'now';
  if (elapsed < MINUTE) return `${Math.floor(elapsed / SECOND)} s`;
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)} min`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)} h`;
  return `${Math.floor(elapsed / DAY)} d`;
}

/** How long it has waited, in the panel's words. */
export function waited(since: number | undefined, now: number): string {
  const said = age(since, now);
  if (said === undefined) return 'Not recorded';
  return said === 'now' ? 'Just now' : `${said} ago`;
}

/** "1 of 13", the open item's place in what the table shows. */
export function position(id: string | undefined, items: readonly TodayItem[]): string | undefined {
  const at = id === undefined ? -1 : items.findIndex((item) => item.id === id);
  return at < 0 ? undefined : `${at + 1} of ${items.length}`;
}

/**
 * The muted line under a title: the project it happens in, then the runtime's recommendation where it gave one, else
 * the item's own detail.
 */
export function under(item: TodayItem): string | undefined {
  const said = item.recommendation === undefined ? item.detail : `Recommend: ${item.recommendation}`;
  const parts = [inLine(item.project), said].filter((part): part is string => part !== undefined);
  return parts.length === 0 ? undefined : parts.join(SEPARATOR);
}

/** How many distinct repositories have a session still open, which is what open projects counts. */
export function openProjects(cards: readonly SessionCard[]): number {
  return new Set(cards.filter((card) => card.state !== 'ended').flatMap((card) => repositoryName(card.repository) ?? [])).size;
}
