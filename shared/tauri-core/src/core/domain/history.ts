/**
 * The exchanges lately, newest first, ported from the Mac's `History` and `Exchange`, so the side panel
 * shows what was asked and answered after the voice has moved on. Plain data, so it is kept as JSON.
 */

export interface Exchange {
  readonly id: string;
  readonly question: string;
  readonly answer: string;
  /** Milliseconds since the epoch. */
  readonly askedAt: number;
  /** When the reply ended; undefined while it is still arriving. */
  readonly answeredAt?: number;
  /** Why no answer came, in words a person can act on; undefined when one did. */
  readonly failure?: string;
}

export interface History {
  readonly exchanges: readonly Exchange[];
}

/** Enough to scroll back through a day of questions, and small enough to read at once. */
export const KEPT_EXCHANGES = 60;

export const NO_HISTORY: History = { exchanges: [] };

export function isAnswering(exchange: Exchange): boolean {
  return exchange.answeredAt === undefined;
}

/** The exchange still arriving, which is always the newest when there is one. */
export function currentExchange(history: History): Exchange | undefined {
  const newest = history.exchanges[0];
  return newest !== undefined && isAnswering(newest) ? newest : undefined;
}

/** A new question: any reply left open ends now, since only one turn runs at a time. */
export function ask(history: History, question: string, at: number, id: string): History {
  const words = question.trim();
  if (words === '') return history;
  const ended = end(history, at);
  return { exchanges: [{ id, question: words, answer: '', askedAt: at }, ...ended.exchanges].slice(0, KEPT_EXCHANGES) };
}

/** The reply so far, kept on the exchange still arriving and dropped when none is. */
export function replied(history: History, answer: string): History {
  const current = currentExchange(history);
  if (current === undefined || answer === current.answer) return history;
  return { exchanges: [{ ...current, answer }, ...history.exchanges.slice(1)] };
}

/**
 * The reply ended. A failure is kept with its reason, so the question can be asked again; an exchange that
 * simply got no words is dropped, since an empty answer is nothing to look back on.
 */
export function end(history: History, at: number, failure?: string): History {
  const current = currentExchange(history);
  if (current === undefined) return history;
  if (failure === undefined && current.answer.trim() === '') return { exchanges: history.exchanges.slice(1) };
  return { exchanges: [{ ...current, answeredAt: at, ...(failure === undefined ? {} : { failure }) }, ...history.exchanges.slice(1)] };
}

/** Whether the words appear in the question or the answer, ignoring case and accents, for a search box. */
export function mentions(text: string, words: string): boolean {
  const wanted = fold(words.trim());
  return wanted === '' || fold(text).includes(wanted);
}

function fold(text: string): string {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

/** The exchanges that mention the words, newest first; all of them when nothing is typed. */
export function matching(history: History, words: string): Exchange[] {
  return history.exchanges.filter((exchange) => mentions(exchange.question, words) || mentions(exchange.answer, words));
}

/** One day of exchanges, named the way a person says it. */
export interface HistoryDay {
  readonly start: number;
  readonly title: string;
  readonly exchanges: readonly Exchange[];
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] as const;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

function startOfDay(at: number): number {
  const day = new Date(at);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

/** The clock time the way the system writes it short, such as 14:05. */
function clock(at: number): string {
  const moment = new Date(at);
  return `${String(moment.getHours()).padStart(2, '0')}:${String(moment.getMinutes()).padStart(2, '0')}`;
}

/** Today with the time of the newest, yesterday, or the weekday and date. */
export function dayTitle(start: number, newest: number | undefined, now: number): string {
  const today = startOfDay(now);
  if (start === today) return newest === undefined ? 'Today' : `Today, ${clock(newest)}`;
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  if (start === yesterday.getTime()) return 'Yesterday';
  const day = new Date(start);
  return `${WEEKDAYS[day.getDay()]} ${day.getDate()} ${MONTHS[day.getMonth()]}`;
}

/** The exchanges that match, grouped by the day they were asked, newest day first. */
export function historyDays(history: History, words: string, now: number): HistoryDay[] {
  const groups = new Map<number, Exchange[]>();
  for (const exchange of matching(history, words)) {
    const start = startOfDay(exchange.askedAt);
    groups.set(start, [...(groups.get(start) ?? []), exchange]);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => b - a)
    .map(([start, exchanges]) => {
      const sorted = [...exchanges].sort((a, b) => b.askedAt - a.askedAt);
      return { start, exchanges: sorted, title: dayTitle(start, sorted[0]?.askedAt, now) };
    });
}

/** Under the question: how long it took and when, or that it is still answering. */
export function exchangeDetail(exchange: Exchange, now: number): string {
  const took = seconds(((exchange.answeredAt ?? now) - exchange.askedAt) / 1_000);
  if (isAnswering(exchange)) return `Answering, ${took}`;
  if (exchange.failure !== undefined) return exchange.failure;
  return `Answered in ${took} · ${clock(exchange.askedAt)}`;
}

function seconds(value: number): string {
  return value < 10 ? `${Math.max(0, value).toFixed(1)}s` : `${Math.round(value)}s`;
}

/** Reads a kept history back, leniently, so a damaged file reads as empty rather than failing. */
export function parseHistory(text: string | null): History {
  if (text === null) return NO_HISTORY;
  try {
    const kept = JSON.parse(text) as { exchanges?: unknown };
    if (!Array.isArray(kept.exchanges)) return NO_HISTORY;
    const exchanges = kept.exchanges.filter(
      (each): each is Exchange =>
        typeof each === 'object' && each !== null && typeof (each as Exchange).id === 'string' && typeof (each as Exchange).question === 'string' && typeof (each as Exchange).askedAt === 'number',
    );
    return { exchanges: exchanges.slice(0, KEPT_EXCHANGES).map((each) => ({ ...each, answer: typeof each.answer === 'string' ? each.answer : '' })) };
  } catch {
    return NO_HISTORY;
  }
}
