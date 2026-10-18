import {
  ASK_ENDS,
  type AskIntent,
  BRIEFING,
  DAEMON_EVENT,
  DAEMON_METHOD,
  PROPOSAL_ANSWER,
  type DaemonAskChunk,
  type DaemonEvent,
  type DaemonRequest,
  type DaemonResponse,
  type ProposalAnswer,
} from '@memnox/core/wire';
import { callLabel } from '../domain/call-label';
import { EarlierAnswer } from '../domain/earlier-answer';
import { quietHere } from '../domain/quiet';
import { SentenceSplitter } from '../domain/sentence-splitter';
import { afterConfirm, heldQuestion, LINES, toolWord } from '../domain/spoken';
import { FRESH_AFTER_MS, WakeLines } from '../domain/wake-lines';
import { nameAlone, withoutLeadingName, withoutTrailingName } from '../domain/wake-word';
import type { Chimes } from './ports/chimes';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { Speaker } from './ports/speaker';
import type { RequestIds } from './request-ids';
import type { ProposalCards } from './proposal-cards';
import type { Signer } from './signer';

/** How a streamed turn ended. */
type Told = { kind: 'spoke' } | { kind: 'silent' } | { kind: 'unreachable' } | { kind: 'refused'; why: string };

/** What the island shows of the voice: what was heard, what is being answered, and why a turn failed. */
export interface TalkState {
  readonly phase: 'idle' | 'listening' | 'thinking' | 'speaking';
  readonly heard: string | undefined;
  readonly reply: string;
  readonly failure: string | undefined;
}

/** Calls `fire` after `ms` unless the returned function is called first; the core has no timers of its own. */
export type Timer = (ms: number, fire: () => void) => () => void;

export interface TalkingOptions {
  readonly now?: () => number;
  readonly timer: Timer;
  /** Longer than any tool takes between two chunks; a turn quiet for longer is stopped. */
  readonly quietLimitMs?: number;
  /** How the person asked to be addressed. */
  readonly owner?: () => string | undefined;
  /** Where a rule or a draft waits to be read before the key is asked; without it they are left alone. */
  readonly cards?: ProposalCards;
  /** Their name, which a greeting keeps and says far less often than the address. */
  readonly name?: () => string | undefined;
  /** The sounds heard before a word is said: sent as their words go, failed as a turn breaks. */
  readonly chimes?: Chimes;
  /** The app in front and its window title as they speak, so a misheard word reads in context. */
  readonly lookingAt?: () => Promise<{ app?: string; title?: string } | undefined>;
  /** The hour of the day, for a greeting; the clock the test sets otherwise. */
  readonly hour?: () => number;
}

/** How a person asked, set by the keys they held and never by a word they said. */
export interface AskOptions {
  readonly intent?: AskIntent;
}

/** A greeting holds for this long, the same span the daemon counts as one sitting. */
const GREETING_HOLDS_MS = 30 * 60 * 1_000;
/** How long the front app may take to read before the question goes without it. */
const LOOKING_AT_PATIENCE_MS = 150;

/** Long enough to say "yes, go ahead" and have the brain propose it. */
export const ANSWER_WINDOW_MS = 120_000;
const QUIET_LIMIT_MS = 75_000;
/** The operator tools the brain calls when the person is done, and when they paused mid thought. */
const END_TOOL = 'end_conversation';
const HOLD_TOOL = 'keep_listening';
/** How the daemon refuses a brief about a call already answered or run out. */
const NOTHING_TO_BRIEF = 'nothing to brief about';
const UNKNOWN_METHOD = 'no method';

class Stalled extends Error {}

/**
 * Talks and listens on the person's behalf, ported from the Mac's `Conversation`: what they said goes
 * whole to their own brain, what waits on them is said out loud, and an allow is confirmed only after
 * their own words and only with a signature. It holds no policy and never matches words.
 */
export class Talking {
  private current: TalkState = { phase: 'idle', heard: undefined, reply: '', failure: undefined };
  private readonly listeners = new Set<() => void>();
  private readonly now: () => number;
  private readonly quietLimitMs: number;
  private readonly timer: Timer;
  private readonly cards: ProposalCards | undefined;
  private readonly owner: () => string | undefined;
  /** When the person last said something, since an allow may only follow their own words. */
  private lastHeard: number | undefined;
  /** The held call last asked about out loud, so an answer elsewhere ends the question. */
  private asking: string | undefined;
  private interrupted = false;
  /** Set when the brain said the person is done or paused, each read once by the listener. */
  private ending = false;
  private holding = false;
  /** Proposals already put to the key, since the live feed and a catch up can both carry one. */
  private readonly takenUp = new Set<string>();
  /** A phone holding this computer's voice, so nothing an event raises is said here meanwhile. */
  private phoneHolds = false;
  /** Events are said one at a time, in order, so two never talk over each other. */
  private turns: Promise<void> = Promise.resolve();
  /** Set once any words of the reply are said this turn, so a second breath is not taken for a new question. */
  private answering = false;
  private readonly chimes: Chimes | undefined;
  private readonly name: () => string | undefined;
  private readonly lookingAt: (() => Promise<{ app?: string; title?: string } | undefined>) | undefined;
  private readonly hour: () => number;
  /** Said back when the person calls it, the way somebody looks up from their desk. */
  private readonly wakeLines = new WakeLines();
  private lastCalled: number | undefined;
  /** When it last greeted them out loud, which the brain hears of so the same hello is never said twice. */
  private greetedAt: number | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly speaker: Speaker,
    private readonly signer: Signer,
    private readonly ids: RequestIds,
    options: TalkingOptions,
  ) {
    this.timer = options.timer;
    this.cards = options.cards;
    this.now = options.now ?? Date.now;
    this.quietLimitMs = options.quietLimitMs ?? QUIET_LIMIT_MS;
    this.owner = options.owner ?? (() => undefined);
    this.name = options.name ?? (() => undefined);
    this.chimes = options.chimes;
    this.lookingAt = options.lookingAt;
    this.hour = options.hour ?? (() => new Date(this.now()).getHours());
  }

  /** Whether any words of the reply were said this turn. */
  get spokeThisTurn(): boolean {
    return this.answering;
  }

  /** Whether the voice is still asking about this held call, since one answered elsewhere is not waited on. */
  stillAsking(subject: string): boolean {
    return this.asking === subject;
  }

  /** The line for being called now: a greeting for the hour the first time in a while, a word or two after. */
  answerToCall(): string {
    const at = this.now();
    const since = this.lastCalled === undefined ? undefined : at - this.lastCalled;
    this.lastCalled = at;
    if (since === undefined || since >= FRESH_AFTER_MS) this.greetedAt = at;
    return this.wakeLines.line({ address: this.owner(), name: this.name(), hour: this.hour(), sinceLastCallMs: since, at });
  }

  get state(): TalkState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Whether the brain said the person is done, read once, so the listener stops after this reply. */
  takeEnd(): boolean {
    const ending = this.ending;
    this.ending = false;
    return ending;
  }

  /** Whether the brain is waiting for the rest of what they were saying, read once. */
  takeHold(): boolean {
    const holding = this.holding;
    this.holding = false;
    return holding;
  }

  /** The microphone opened or closed, so the island shows it is listening. */
  listening(on: boolean): void {
    if (on && this.current.phase === 'idle') this.update({ phase: 'listening' });
    if (!on && this.current.phase === 'listening') this.update({ phase: 'idle' });
  }

  /**
   * What the person said, whole. No keyword decides anything here; the brain understands it. `finished`
   * says the brain held for the rest and none came; `intent` is how they asked, set by the keys they held.
   */
  async heard(said: string, finished = false, ask: AskOptions = {}): Promise<void> {
    const trimmed = said.trim();
    // Its name called at either end is somebody getting its attention, not part of the question.
    const words = withoutTrailingName(withoutLeadingName(trimmed));
    // A lone "." is the recognizer hearing noise, and answering it makes the voice talk to nobody.
    if (!/\p{L}/u.test(words)) return;
    this.interrupted = false;
    this.answering = false;
    this.lastHeard = this.now();
    // Its name alone is somebody getting its attention, answered the way the wake word is.
    if (nameAlone(trimmed)) {
      await this.say(this.answerToCall());
      return;
    }
    this.chimes?.play('sent');
    this.update({ phase: 'thinking', heard: words, reply: '', failure: undefined });
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.ASK), said: words };
    if (finished) request.finished = true;
    if (ask.intent !== undefined) request.intent = ask.intent;
    if (this.greetedAt !== undefined && this.now() - this.greetedAt < GREETING_HOLDS_MS) request.greeted = true;
    const front = await this.front();
    if (front?.app !== undefined) request.lookingAt = front.app;
    if (front?.title !== undefined) request.lookingAtWindow = front.title;
    const told = await this.speakStream(request);
    this.update({ phase: 'idle', failure: failureOf(told) });
    // Heard before the apology starts, so a broken turn never sounds like a slow one.
    if (told.kind !== 'spoke' && told.kind !== 'silent') this.chimes?.play('failed');
    if (told.kind === 'unreachable') await this.say(LINES.unreachable);
    if (told.kind === 'refused') await this.say(told.why === LINES.tooOld || told.why === LINES.stalled ? told.why : `My apologies, I could not ask that: ${told.why}.`);
  }

  /** The person started talking over the answer: the voice stops now and the brain stops too. */
  async interrupt(): Promise<void> {
    this.interrupted = true;
    this.speaker.stop();
    await requestOnce(this.link, this.request(DAEMON_METHOD.CANCEL)).catch(() => undefined);
  }

  /** A held call answered on the island, so the voice stops asking about it. */
  answeredByHand(subject: string): void {
    if (this.asking !== subject) return;
    this.asking = undefined;
    this.speaker.stop();
  }

  /** Something that started or stopped waiting on the person, taken in order behind whatever is being said. */
  handle(event: DaemonEvent): Promise<void> {
    this.turns = this.turns.then(() => this.take(event)).catch(() => undefined);
    return this.turns;
  }

  private async take(event: DaemonEvent): Promise<void> {
    if (event.voiceOn !== undefined) {
      this.phoneHolds = event.voiceOn.holding;
      return;
    }
    if (event.kind === DAEMON_EVENT.SETTLED) return this.settled(event);
    if (event.kind === DAEMON_EVENT.PROPOSAL) return this.proposal(event);
    // A phone's turn, a drive grant and a sign in are shown rather than said; a phone's event is left to it.
    if (quietHere(event, this.phoneHolds) || event.phoneTurn !== undefined || event.drivenBy !== undefined) return;
    if (event.kind === DAEMON_EVENT.HELD) return this.held(event);
    if (event.kind === DAEMON_EVENT.PAUSED) return this.briefed(event, BRIEFING.PAUSED, `I paused a session: ${event.summary}.`);
    if (event.kind === DAEMON_EVENT.NOTICE && event.signedIn === undefined) return this.briefed(event, BRIEFING.NOTICE, event.summary);
  }

  /** Told by their own brain with what the session has been doing; the facts alone if it cannot. */
  private async held(event: DaemonEvent): Promise<void> {
    this.asking = event.subject;
    this.interrupted = false;
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.BRIEF), briefing: BRIEFING.HELD, subject: event.subject };
    const told = await this.speakStream(request);
    // Nothing to brief is a call already answered or run out, and asking about it asks about nothing.
    if (told.kind === 'refused' && told.why === NOTHING_TO_BRIEF) {
      this.asking = undefined;
      return;
    }
    if (told.kind !== 'spoke' && !this.interrupted && this.asking === event.subject) {
      await this.say(heldQuestion(this.owner(), event, callLabel(event.agentName ?? event.agent)));
    }
  }

  private async briefed(event: DaemonEvent, briefing: string, otherwise: string): Promise<void> {
    this.interrupted = false;
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.BRIEF), briefing, subject: event.subject };
    if ((await this.speakStream(request)).kind !== 'spoke' && !this.interrupted) await this.say(otherwise);
  }

  private settled(event: DaemonEvent): void {
    this.cards?.remove(event.subject);
    if (this.asking !== event.subject) return;
    this.asking = undefined;
    this.speaker.stop();
  }

  /**
   * Only after the person spoke: an allow nobody asked for is declined, never put to the key. A phone's
   * proposal is that phone's to answer. A rule or a draft goes on its card, where the key is asked only
   * once the person picked where it holds or pressed Send; a teammate's call waits for a screen that has it.
   */
  private async proposal(event: DaemonEvent): Promise<void> {
    if (quietHere(event, this.phoneHolds)) return;
    const asked = this.lastHeard !== undefined && this.now() - this.lastHeard < ANSWER_WINDOW_MS;
    if (!asked) return this.decline(event);
    if (event.teamAnswer !== undefined) return this.say(LINES.needsCard);
    if (event.rule !== undefined || event.work !== undefined) {
      if (this.cards?.show(event) !== true) await this.say(LINES.needsCard);
      return;
    }
    if (this.takenUp.has(event.subject)) return;
    this.takenUp.add(event.subject);
    // The read back says what the prompt is for, so the prompt waits until it has been said.
    await this.speaker.drained();
    await this.confirm(event);
  }

  private async confirm(event: DaemonEvent): Promise<void> {
    let answer: ProposalAnswer = PROPOSAL_ANSWER.CONFIRMED;
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.CONFIRM), subject: event.subject };
    if (event.withinSession !== true) {
      const signing = await this.signer.sign(event.subject, PROPOSAL_ANSWER.CONFIRMED, event.summary);
      if (signing.kind === 'refused') return this.say(signing.why);
      if (signing.kind === 'signed') request.signature = signing.signature;
      else answer = PROPOSAL_ANSWER.DECLINED;
    }
    request.answer = answer;
    const response = await requestOnce(this.link, request).catch(() => undefined);
    const earlier = EarlierAnswer.from(response);
    if (earlier !== undefined) return earlier.matches(answer) ? undefined : this.say(earlier.line);
    if (response?.ok === true) return this.say(afterConfirm(answer, response.outcome));
    await this.say(`My apologies, that was not confirmed: ${response?.error ?? 'Memnox did not answer'}.`);
  }

  private async decline(event: DaemonEvent): Promise<void> {
    const request = { ...this.request(DAEMON_METHOD.CONFIRM), subject: event.subject, answer: PROPOSAL_ANSWER.DECLINED };
    await requestOnce(this.link, request).catch(() => undefined);
    await this.say(LINES.unasked);
  }

  /** Streams a turn into speech, sentence by sentence, and says how it ended. */
  private async speakStream(request: DaemonRequest): Promise<Told> {
    const sentences = new SentenceSplitter();
    let spoke = false;
    try {
      for await (const response of this.quieted(this.link.stream(request))) {
        if (!response.ok && response.error !== undefined) return refusal(response.error);
        // An older daemon answers a method it does not know with a bare ok and nothing more.
        if (response.chunk === undefined) return { kind: 'refused', why: LINES.tooOld };
        if (response.chunk.kind === 'text' && (response.chunk.text ?? '') !== '') spoke = true;
        if (await this.play(response.chunk, sentences)) break;
      }
    } catch (error) {
      if (!(error instanceof Stalled)) return spoke ? { kind: 'spoke' } : { kind: 'unreachable' };
      await requestOnce(this.link, this.request(DAEMON_METHOD.CANCEL)).catch(() => undefined);
      this.flow(sentences.flush());
      await this.speaker.drained();
      return spoke ? { kind: 'spoke' } : { kind: 'refused', why: LINES.stalled };
    }
    const rest = sentences.flush();
    if (rest !== undefined && !this.interrupted) spoke = true;
    this.flow(rest);
    await this.speaker.drained();
    return spoke ? { kind: 'spoke' } : { kind: 'silent' };
  }

  /** Plays one chunk; true once the turn is over. */
  private async play(chunk: DaemonAskChunk, sentences: SentenceSplitter): Promise<boolean> {
    if (chunk.kind === 'text') {
      // After keep_listening nothing more is said this turn, since anything would talk over them.
      if (this.holding || this.interrupted) return false;
      if ((chunk.text ?? '') !== '') this.answering = true;
      this.update({ phase: 'speaking', reply: this.current.reply + (chunk.text ?? '') });
      for (const sentence of sentences.push(chunk.text ?? '')) this.flow(sentence);
    } else if (chunk.kind === 'tool') {
      // Whatever came before a tool call is a sentence on its own, even with no space after its "?".
      this.flow(sentences.flush());
      if (toolWord(chunk.tool) === END_TOOL) this.ending = true;
      if (toolWord(chunk.tool) === HOLD_TOOL) this.holding = true;
    } else if (chunk.kind === 'limited') {
      this.flow(sentences.flush());
      await this.say(LINES.limited);
    } else if (chunk.kind === 'failed' && !this.interrupted) {
      // A turn the person cut short was stopped on purpose, so it is not reported as broken.
      this.flow(sentences.flush());
      await this.say(`My apologies, that did not work: ${chunk.text ?? 'the brain stopped'}.`);
    }
    return ASK_ENDS.includes(chunk.kind);
  }

  /** The daemon's lines as they come, ended with `Stalled` once none arrived for the quiet limit. */
  private async *quieted(upstream: AsyncIterable<DaemonResponse>): AsyncIterable<DaemonResponse> {
    const lines = upstream[Symbol.asyncIterator]();
    for (;;) {
      let cancel: () => void = () => undefined;
      const stalled = new Promise<never>((_, reject) => {
        cancel = this.timer(this.quietLimitMs, () => reject(new Stalled()));
      });
      try {
        const next = await Promise.race([lines.next(), stalled]);
        if (next.done === true) return;
        yield next.value;
      } finally {
        cancel();
      }
    }
  }

  private flow(sentence: string | undefined): void {
    if (sentence !== undefined && !this.interrupted) this.speaker.queue(sentence);
  }

  private async say(sentence: string): Promise<void> {
    this.speaker.queue(sentence);
    await this.speaker.drained();
  }

  /** The app in front, read quickly or not at all, since the question must never wait on it. */
  private async front(): Promise<{ app?: string; title?: string } | undefined> {
    if (this.lookingAt === undefined) return undefined;
    let cancel: () => void = () => undefined;
    const late = new Promise<undefined>((resolve) => {
      cancel = this.timer(LOOKING_AT_PATIENCE_MS, () => resolve(undefined));
    });
    try {
      return await Promise.race([this.lookingAt().catch(() => undefined), late]);
    } finally {
      cancel();
    }
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    const owner = this.owner();
    return owner === undefined ? { id: this.ids.next(), method } : { id: this.ids.next(), method, owner };
  }

  private update(change: Partial<TalkState>): void {
    this.current = { ...this.current, ...change };
    for (const listener of this.listeners) listener();
  }
}

function refusal(error: string): Told {
  return { kind: 'refused', why: error.startsWith(UNKNOWN_METHOD) ? LINES.tooOld : error };
}

/** Why a turn got no answer, as the island shows it; undefined when it was answered or simply quiet. */
function failureOf(told: Told): string | undefined {
  if (told.kind === 'unreachable') return 'Memnox could not be reached on this computer';
  if (told.kind === 'refused') return told.why === LINES.stalled ? 'No answer came, so it stopped waiting' : told.why;
  return undefined;
}
