import {
  confirmationMessage,
  DAEMON_EVENT,
  DAEMON_METHOD,
  HOLD_ANSWER,
  type DaemonEvent,
  type DaemonRequest,
  type DaemonResponse,
  type HoldAnswer,
} from '@memnox/core/wire';
import { consentReason } from '../domain/call-label';
import { EarlierAnswer } from '../domain/earlier-answer';
import { heldCard, type HeldCard } from '../domain/held-card';
import { ANOTHER_KEY_LINE, keyStatusOf, type KeyStatus } from '../domain/key-status';
import { WaitingCalls } from '../domain/waiting-calls';
import type { ConfirmKey } from './ports/confirm-key';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import { RequestIds } from './request-ids';

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
}

/** Said when this computer has no key the operating system guards, so an allow has to come from elsewhere. */
export const NO_KEY_LINE =
  'This computer has no key to sign a yes with, so allow it from the terminal or your phone.';
const NOT_ANSWERED = 'Memnox did not answer';

type Signing = { kind: 'signed'; signature: string } | { kind: 'refused'; outcome: HeldOutcome };

/**
 * The held calls waiting on the person and their answers to them, ported from the Mac's
 * `Conversation`: a deny goes as it is, and an allow only with a signature over exactly this
 * call, unless the daemon placed it inside its repository. It holds no policy: the daemon decides
 * what is held, and this only shows it and carries the person's answer back, signed.
 */
export class HeldCalls {
  private current: HeldState = { waiting: WaitingCalls.empty(), key: undefined, connected: false };
  private readonly listeners = new Set<() => void>();

  constructor(
    private readonly link: DaemonLink,
    private readonly key: ConfirmKey,
    private readonly ids: RequestIds = new RequestIds(),
  ) {}

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
        if (response.event !== undefined) this.handle(response.event);
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
    for (const event of response.waiting ?? []) this.handle(event);
  }

  /**
   * A held call joins the queue and a settled one leaves it. A proposal is left alone: on the Mac a
   * proposal is confirmed only after the person's own spoken words, and this app does not listen yet,
   * so nothing it did not ask for is ever put to the key.
   */
  handle(event: DaemonEvent): void {
    if (event.kind === DAEMON_EVENT.HELD) {
      this.update({ waiting: this.current.waiting.add(heldCard(event), event.subject, heldCard(event).label) });
    } else if (event.kind === DAEMON_EVENT.SETTLED) {
      this.update({ waiting: this.current.waiting.remove(event.subject) });
    }
  }

  step(offset: number): void {
    this.update({ waiting: this.current.waiting.step(offset) });
  }

  /** Registers this computer's key, which the daemon trusts on first use. */
  async registerKey(): Promise<KeyStatus> {
    const point = await this.key.publicPoint();
    const status = point === undefined ? { kind: 'no-key' as const } : await this.register(point);
    this.update({ key: status });
    return status;
  }

  private async register(point: string): Promise<KeyStatus> {
    const request = { ...this.request(DAEMON_METHOD.REGISTER_KEY), point };
    const response = await requestOnce(this.link, request).catch(() => undefined);
    return response === undefined ? { kind: 'unreachable' } : keyStatusOf(response);
  }

  /** A held call answered with a button. A yes that reaches past its session carries a signature, or is not sent. */
  async answer(subject: string, answer: HoldAnswer): Promise<HeldOutcome> {
    const card = this.current.waiting.entries.find((entry) => entry.subject === subject)?.card;
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.CONFIRM), subject, answer };
    // A card that is gone is signed for, since only the daemon's word that it stays inside its session waives the key.
    if (answer !== HOLD_ANSWER.DENY && card?.withinSession !== true) {
      const reason = consentReason(card?.label ?? 'this call', card?.what, answer);
      const signing = await this.signature(subject, answer, reason);
      if (signing.kind === 'refused') return signing.outcome;
      request.signature = signing.signature;
    }
    const response = await requestOnce(this.link, request).catch(() => undefined);
    return this.settle(subject, response);
  }

  private settle(subject: string, response: DaemonResponse | undefined): HeldOutcome {
    const earlier = EarlierAnswer.from(response);
    if (earlier !== undefined) {
      this.update({ waiting: this.current.waiting.remove(subject) });
      return { kind: 'answered-elsewhere', earlier };
    }
    if (response?.ok !== true) return { kind: 'failed', why: response?.error ?? NOT_ANSWERED };
    this.update({ waiting: this.current.waiting.remove(subject) });
    return { kind: 'answered' };
  }

  /** The key over this answer, asked only once the daemon trusts it: a signature from any other key is refused after the prompt. */
  private async signature(subject: string, answer: HoldAnswer, reason: string): Promise<Signing> {
    const status = await this.registerKey();
    if (status.kind === 'another-key') return { kind: 'refused', outcome: { kind: 'failed', why: ANOTHER_KEY_LINE } };
    if (status.kind === 'no-key') return { kind: 'refused', outcome: { kind: 'failed', why: NO_KEY_LINE } };
    const signature = await this.key.sign(confirmationMessage(subject, answer), reason).catch(() => undefined);
    if (signature === undefined) return { kind: 'refused', outcome: { kind: 'cancelled' } };
    return { kind: 'signed', signature };
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    return { id: this.ids.next(), method };
  }

  private update(change: Partial<HeldState>): void {
    this.current = { ...this.current, ...change };
    for (const listener of this.listeners) listener();
  }
}
