import { DAEMON_EVENT, DAEMON_METHOD, type DaemonEvent, type DaemonRequest } from '@memnox/core/wire';
import { answering, joinedPicks, nextQuestion, questionCard, type QuestionCard } from '../domain/agent-question';
import { EarlierAnswer } from '../domain/earlier-answer';
import { ISLAND_TIMING } from '../domain/island-layout';
import type { HeldOutcome } from './held-calls';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Timer } from './talking';

export interface QuestionState {
  /** The agent's question on screen, undefined once every question has its answer. */
  readonly card: QuestionCard | undefined;
  /** The options ticked on a question that takes several, sent together with Done. */
  readonly ticked: ReadonlySet<string>;
  /** Why the last pick did not go through, said on the card for a moment. */
  readonly error: string | undefined;
  /** A pick is on its way, so a second press is not sent behind it. */
  readonly answering: boolean;
}

const NOT_ANSWERED = 'Memnox did not answer';

/**
 * An agent's own question, asked here as taps while the voice reads it, so either answer lands. Ported
 * from the Mac's `IslandPanel.question` and `Conversation.answerQuestion`: a pick is a CONFIRM naming the
 * question by number, carrying the option's words. No key signs it, since it allows nothing; the agent
 * reads the answer as if the person had picked it in its own terminal.
 */
export class AgentQuestions {
  private current: QuestionState = { card: undefined, ticked: new Set(), error: undefined, answering: false };
  private readonly listeners = new Set<() => void>();
  private clearing: (() => void) | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly timer: Timer,
    /** Picked by hand, so the voice stops reading out a question that already has its answer. */
    private readonly answeredByHand: (subject: string) => void = () => undefined,
  ) {}

  get state(): QuestionState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** A question with something to pick opens the island on it; a settled subject takes it away. */
  handle(event: DaemonEvent): void {
    const card = questionCard(event);
    if (card !== undefined) {
      this.update({ card: nextQuestion(card) === undefined ? undefined : card, ticked: new Set(), error: undefined });
      return;
    }
    // Answered by voice or in the agent's own picker, or run out: nothing is left to ask.
    if (event.kind === DAEMON_EVENT.SETTLED && this.current.card?.subject === event.subject) this.clear();
  }

  /** A choice ticked or unticked on a question that takes several. */
  toggle(label: string): void {
    const ticked = new Set(this.current.ticked);
    if (ticked.has(label)) ticked.delete(label);
    else ticked.add(label);
    this.update({ ticked });
  }

  /** One choice picked on a single choice question. */
  pick(label: string): Promise<HeldOutcome> {
    return this.send(label);
  }

  /** Done on a question that takes several: the ticked choices go as one answer, in the agent's order. */
  done(): Promise<HeldOutcome> {
    const next = this.current.card === undefined ? undefined : nextQuestion(this.current.card);
    if (next === undefined || this.current.ticked.size === 0) return Promise.resolve({ kind: 'cancelled' });
    return this.send(joinedPicks(this.current.ticked, next.item));
  }

  /** The person looks at it in the agent's own window instead; the card goes and the agent still waits there. */
  dismiss(): void {
    this.clear();
  }

  private async send(answer: string): Promise<HeldOutcome> {
    const card = this.current.card;
    const next = card === undefined ? undefined : nextQuestion(card);
    if (card === undefined || next === undefined || this.current.answering) return { kind: 'cancelled' };
    this.update({ answering: true });
    const request: DaemonRequest = { ...this.request(DAEMON_METHOD.CONFIRM), subject: card.subject, answer, questionNumber: next.number };
    const response = await requestOnce(this.link, request).catch(() => undefined);
    this.update({ answering: false });
    // The card was taken while the pick was on its way, so there is nothing left to move on.
    if (this.current.card?.subject !== card.subject) return { kind: 'answered' };
    const earlier = EarlierAnswer.from(response);
    const outcome: HeldOutcome =
      earlier !== undefined ? { kind: 'answered-elsewhere', earlier } : response?.ok === true ? { kind: 'answered' } : { kind: 'failed', why: response?.error ?? NOT_ANSWERED };
    if (outcome.kind === 'failed') {
      this.update({ error: outcome.why });
      this.clearing?.();
      this.clearing = this.timer(ISLAND_TIMING.settledFor, () => this.update({ error: undefined }));
      return outcome;
    }
    this.answeredByHand(card.subject);
    const moved = answering(card, next.number, answer);
    this.update({ card: nextQuestion(moved) === undefined ? undefined : moved, ticked: new Set(), error: undefined });
    return outcome;
  }

  private clear(): void {
    this.clearing?.();
    this.update({ card: undefined, ticked: new Set(), error: undefined, answering: false });
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    return { id: this.ids.next(), method };
  }

  private update(changes: Partial<QuestionState>): void {
    this.current = { ...this.current, ...changes };
    for (const listener of this.listeners) listener();
  }
}
