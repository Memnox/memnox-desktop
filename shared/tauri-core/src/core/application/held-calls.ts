import {
  DAEMON_EVENT,
  DAEMON_METHOD,
  HOLD_ANSWER,
  type DaemonEvent,
  type DaemonRequest,
  type DaemonResponse,
} from '@memnox/core/wire';
import { consentReason, FROM_NOW_ON, ON_THIS_COMPUTER, placeMachine, raisedOn, type CallPlace, type HeldAnswer } from '../domain/call-label';
import { EarlierAnswer } from '../domain/earlier-answer';
import { heldCard, teamHeldCard, teamMachine, type HeldCard } from '../domain/held-card';
import type { WorkspaceHeldCall } from '../domain/workspace-wire';
import { ISLAND_TIMING } from '../domain/island-layout';
import type { KeyStatus } from '../domain/key-status';
import { settledLine, SETTLED_UNKNOWN } from '../domain/settled-line';
import { WaitingCalls } from '../domain/waiting-calls';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Signer } from './signer';
import type { Timer } from './talking';

/** How a press on a held call ended. */
export type HeldOutcome =
  | { kind: 'answered' }
  /** Somebody answered first, from the terminal, a phone or the workspace, and that answer stands. */
  | { kind: 'answered-elsewhere'; earlier: EarlierAnswer }
  /** The person cancelled the prompt, so nothing was sent and the call still waits. */
  | { kind: 'cancelled' }
  | { kind: 'failed'; why: string };

/** Everything the island draws, replaced whole on every change so a screen compares one with the next. */
export interface HeldState {
  readonly waiting: WaitingCalls<HeldCard>;
  readonly key: KeyStatus | undefined;
  /** Whether the live feed of what waits is open. */
  readonly connected: boolean;
  /** An allow is being signed, so the answers dim and nothing steps until it ends. */
  readonly answering: boolean;
  /** The call answered from these buttons, which never shows a settled note of its own. */
  readonly pressed: string | undefined;
  /** The shown call was settled elsewhere, and its card says so for a moment before it goes. */
  readonly settled: { readonly subject: string; readonly note: string } | undefined;
}

export interface HeldCallsOptions {
  /** Keeps a card settled elsewhere up long enough to read; without one it goes at once. */
  readonly timer?: Timer;
  /** Where answers go: the link that routes each subject back to the machine that raised it. The feed's own link otherwise. */
  readonly answers?: DaemonLink;
  /** Whether an event of this computer's own feed reaches the island, and the place to remember it by. */
  readonly accept?: (event: DaemonEvent) => boolean;
  /** Teammates' calls the workspace routed here, answered through it and never through a daemon. */
  readonly team?: {
    owns(subject: string): boolean;
    answer(subject: string, answer: typeof HOLD_ANSWER.ONCE | typeof HOLD_ANSWER.SESSION | typeof HOLD_ANSWER.DENY, reason: string): Promise<HeldOutcome>;
  };
}

const NOT_ANSWERED = 'Memnox did not answer';

/**
 * The held calls waiting on the person and their answers to them, ported from the Mac's
 * `Conversation`: a deny goes as it is, and an allow only with a signature over exactly this
 * call, unless the daemon placed it inside its repository. It holds no policy: the daemon decides
 * what is held, and this only shows it and carries the person's answer back, signed.
 */
export class HeldCalls {
  private current: HeldState = {
    waiting: WaitingCalls.empty(),
    key: undefined,
    connected: false,
    answering: false,
    pressed: undefined,
    settled: undefined,
  };
  private settling: (() => void) | undefined;
  private readonly listeners = new Set<() => void>();
  private readonly eventListeners = new Set<(event: DaemonEvent) => void>();

  constructor(
    private readonly link: DaemonLink,
    private readonly signer: Signer,
    private readonly ids: RequestIds,
    private readonly options: HeldCallsOptions = {},
  ) {}

  /** The key's standing, as the signer last found it; the composition root wires the signer's reports here. */
  keyChanged(status: KeyStatus): void {
    this.update({ key: status });
  }

  /** Every event of the live feed once the queue has taken it, so the voice hears the same feed. */
  observeEvents(listener: (event: DaemonEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  get state(): HeldState {
    return this.current;
  }

  /** Called after every change; returns what stops it. */
  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * One sitting with the daemon: what already waits, then every change as it happens, until the
   * daemon closes the feed. The caller opens the next one, since a restarted daemon is a new feed.
   */
  async watch(): Promise<void> {
    try {
      await this.catchUp();
      for await (const response of this.link.stream(this.request(DAEMON_METHOD.SUBSCRIBE))) {
        this.update({ connected: true });
        if (response.event === undefined) continue;
        if (this.options.accept?.(response.event) === false) continue;
        this.handle(response.event);
        for (const listener of this.eventListeners) listener(response.event);
      }
    } catch {
      // The daemon is down or went away; the caller tries again.
    } finally {
      this.update({ connected: false });
    }
  }

  /** What waits right now, so a call held before this app opened is on screen too. */
  private async catchUp(): Promise<void> {
    const response = await requestOnce(this.link, this.request(DAEMON_METHOD.WAITING));
    for (const event of response.waiting ?? []) if (this.options.accept?.(event) !== false) this.handle(event);
  }

  /**
   * A held call joins the queue and a settled one leaves it. A proposal is left alone: on the Mac a
   * proposal is confirmed only after the person's own spoken words, and this app does not listen yet,
   * so nothing it did not ask for is ever put to the key.
   */
  handle(event: DaemonEvent, place: CallPlace = ON_THIS_COMPUTER): void {
    if (event.kind === DAEMON_EVENT.HELD) {
      // The card on screen stays while one is being answered or says how it was settled.
      const keepShown = this.current.answering || this.current.settled !== undefined;
      // The queue's header counts by the machine each call waits on: this computer, or the server that raised it.
      this.update({ waiting: this.current.waiting.add(heldCard(event, place), event.subject, placeMachine(place), keepShown) });
    } else if (event.kind === DAEMON_EVENT.SETTLED) {
      // The daemon does not say who answered or whether it ran out, so the card claims neither.
      this.release(event.subject, SETTLED_UNKNOWN);
    }
  }

  /** An event a paired server raised, labelled with its name and told to the voice like one of this computer's. */
  fromServer(event: DaemonEvent, server: string): void {
    this.handle(event, raisedOn(server));
    for (const listener of this.eventListeners) listener(event);
  }

  /** A teammate's call the workspace routed here, queued beside this computer's and the servers'. */
  holdTeam(call: WorkspaceHeldCall): void {
    const keepShown = this.current.answering || this.current.settled !== undefined;
    this.update({ waiting: this.current.waiting.add(teamHeldCard(call), call.id, teamMachine(call), keepShown) });
  }

  /** A call settled somewhere this feed does not hear, such as the workspace, with the note its card shows, or none. */
  settledElsewhere(subject: string, note: string | undefined): void {
    this.release(subject, note);
  }

  /** One call older for a positive offset, newer for a negative one; nothing moves while one is being signed. */
  step(offset: number): void {
    if (this.current.answering || this.current.settled !== undefined) return;
    this.update({ waiting: this.current.waiting.step(offset) });
  }

  /** Registers this computer's key, which the daemon trusts on first use. */
  registerKey(): Promise<KeyStatus> {
    return this.signer.registerKey();
  }

  /** A held call answered with a button. A yes that reaches past its session carries a signature, or is not sent. */
  async answer(subject: string, answer: HeldAnswer): Promise<HeldOutcome> {
    this.update({ answering: answer !== HOLD_ANSWER.DENY, pressed: subject });
    const outcome = await this.send(subject, answer);
    this.update({ answering: false });
    if (outcome.kind === 'answered-elsewhere') {
      // Somebody got there first, so the card says how it was settled before it goes.
      this.update({ pressed: undefined });
      this.release(subject, settledLine(outcome.earlier.word));
    } else if (outcome.kind === 'answered') {
      this.release(subject);
    } else {
      this.update({ pressed: undefined });
    }
    return outcome;
  }

  private async send(subject: string, answer: HeldAnswer): Promise<HeldOutcome> {
    const card = this.current.waiting.entries.find((entry) => entry.subject === subject)?.card;
    const team = this.options.team;
    if (team?.owns(subject) === true) {
      // A teammate's call has no rule here to relax, so from now on is a yes to this call there, and an edit is not one the workspace takes.
      const said = answer === FROM_NOW_ON || answer === HOLD_ANSWER.EDIT ? HOLD_ANSWER.ONCE : answer;
      return team.answer(subject, said, consentReason(card?.label ?? 'this call', card?.what, said));
    }
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.CONFIRM), subject, answer };
    // A card that is gone is signed for, since only the daemon's word that it stays inside its session waives the key.
    if (answer !== HOLD_ANSWER.DENY && card?.withinSession !== true) {
      const reason = consentReason(card?.label ?? 'this call', card?.what, answer);
      const signing = await this.signer.sign(subject, answer, reason);
      if (signing.kind === 'cancelled') return { kind: 'cancelled' };
      if (signing.kind === 'refused') return { kind: 'failed', why: signing.why };
      request.signature = signing.signature;
    }
    const response = await requestOnce(this.options.answers ?? this.link, request).catch(() => undefined);
    return this.settle(response);
  }

  private settle(response: DaemonResponse | undefined): HeldOutcome {
    const earlier = EarlierAnswer.from(response);
    if (earlier !== undefined) return { kind: 'answered-elsewhere', earlier };
    if (response?.ok !== true) return { kind: 'failed', why: response?.error ?? NOT_ANSWERED };
    return { kind: 'answered' };
  }

  /**
   * The call stopped waiting and its card goes. `note` says it was settled elsewhere, shown on the card
   * for a moment first when it is the one on screen; a call answered from these buttons never shows one.
   */
  private release(subject: string, note?: string): void {
    const shown = this.current.waiting.shown?.subject === subject;
    const timer = this.options.timer;
    if (note !== undefined && shown && this.current.pressed !== subject && timer !== undefined) {
      this.settling?.();
      this.update({ settled: { subject, note }, answering: false });
      this.settling = timer(ISLAND_TIMING.settledFor, () => this.drop(subject));
      return;
    }
    if (shown) this.settling?.();
    this.drop(subject);
  }

  /** Takes a call off at once, with whatever note its card was showing. */
  private drop(subject: string): void {
    const change: { -readonly [K in keyof HeldState]?: HeldState[K] } = { waiting: this.current.waiting.remove(subject) };
    if (this.current.settled?.subject === subject) change.settled = undefined;
    if (this.current.pressed === subject) change.pressed = undefined;
    this.update(change);
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    return { id: this.ids.next(), method };
  }

  private update(change: Partial<HeldState>): void {
    this.current = { ...this.current, ...change };
    for (const listener of this.listeners) listener();
  }
}
