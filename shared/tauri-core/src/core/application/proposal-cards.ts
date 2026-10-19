import { DAEMON_METHOD, PROPOSAL_ANSWER, type DaemonEvent, type DaemonRequest, type DaemonResponse } from '@memnox/core/wire';
import { EarlierAnswer } from '../domain/earlier-answer';
import { afterRule, draftReason, proposalCard, ruleReason, SENT_LINE, type ProposalCard } from '../domain/proposal-card';
import type { HeldOutcome } from './held-calls';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { Speaker } from './ports/speaker';
import type { RequestIds } from './request-ids';
import type { Signer } from './signer';

const NOT_ANSWERED = 'Memnox did not answer';

/**
 * The proposals that wait on a card: a rule and where it could hold, and a message about to go out in
 * the person's name. Ported from the Mac: a rule goes in force only with a signature over the scope
 * picked, a Send only with a signature over exactly the words sent, and closing either goes unsigned.
 */
export class ProposalCards {
  private current: readonly ProposalCard[] = [];
  private readonly listeners = new Set<() => void>();

  constructor(
    private readonly link: DaemonLink,
    private readonly signer: Signer,
    private readonly speaker: Speaker,
    private readonly ids: RequestIds,
  ) {}

  /** Newest last; the island shows the newest. */
  get cards(): readonly ProposalCard[] {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Puts a proposal on its card; false for one that needs no card. */
  show(event: DaemonEvent): boolean {
    const card = proposalCard(event);
    if (card === undefined) return false;
    this.set([...this.current.filter((each) => each.subject !== card.subject), card]);
    return true;
  }

  /** A proposal answered elsewhere or run out. */
  remove(subject: string): void {
    if (this.current.some((card) => card.subject === subject)) this.set(this.current.filter((card) => card.subject !== subject));
  }

  /** A rule put in force where the person picked, or left out when `scopeId` is undefined. */
  async answerRule(subject: string, scopeId: string | undefined): Promise<HeldOutcome> {
    const card = this.current.find((each) => each.subject === subject);
    const scope = card?.kind === 'rule' ? card.rule.scopes.find((each) => each.id === scopeId) : undefined;
    if (scopeId !== undefined && (card?.kind !== 'rule' || scope === undefined)) return { kind: 'failed', why: 'That place is not one this rule offers.' };
    const request: DaemonRequest = { ...this.request(), subject, answer: scope?.id ?? PROPOSAL_ANSWER.DECLINED };
    if (card?.kind === 'rule' && scope !== undefined) {
      const signing = await this.signer.sign(subject, scope.id, ruleReason(card.rule, scope));
      if (signing.kind === 'cancelled') return { kind: 'cancelled' };
      if (signing.kind === 'refused') return { kind: 'failed', why: signing.why };
      request.signature = signing.signature;
    }
    const chose = scope === undefined ? PROPOSAL_ANSWER.DECLINED : PROPOSAL_ANSWER.CONFIRMED;
    return this.settle(subject, chose, await this.send(request), afterRule(scope));
  }

  /** A draft sent, with the words and, on a mail, the addresses the person rewrote, or closed and sent nowhere. */
  async answerDraft(subject: string, send: boolean, edited?: string, editedTo?: string): Promise<HeldOutcome> {
    const card = this.current.find((each) => each.subject === subject);
    const answer = send ? PROPOSAL_ANSWER.CONFIRMED : PROPOSAL_ANSWER.DECLINED;
    const request: DaemonRequest = { ...this.request(), subject, answer };
    if (send) {
      // Only a Send carries rewritten words, since closing a draft sends nothing at all.
      if (edited !== undefined) request.edited = edited;
      if (editedTo !== undefined) request.editedTo = editedTo;
      const typed = editedTo?.split(',');
      const reason = card?.kind === 'work' ? draftReason(card.work, typed) : 'send this message';
      const signing = await this.signer.sign(subject, answer, reason, edited, editedTo);
      if (signing.kind === 'cancelled') return { kind: 'cancelled' };
      if (signing.kind === 'refused') return { kind: 'failed', why: signing.why };
      request.signature = signing.signature;
    }
    return this.settle(subject, answer, await this.send(request), send ? SENT_LINE : undefined);
  }

  private async settle(subject: string, chose: string, response: DaemonResponse | undefined, line: string | undefined): Promise<HeldOutcome> {
    const earlier = EarlierAnswer.from(response);
    if (earlier !== undefined) {
      this.remove(subject);
      if (!earlier.matches(chose)) this.speaker.queue(earlier.line);
      return { kind: 'answered-elsewhere', earlier };
    }
    if (response?.ok !== true) return { kind: 'failed', why: response?.error ?? NOT_ANSWERED };
    this.remove(subject);
    if (line !== undefined) this.speaker.queue(line);
    return { kind: 'answered' };
  }

  private send(request: DaemonRequest): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, request).catch(() => undefined);
  }

  private request(): DaemonRequest {
    return { id: this.ids.next(), method: DAEMON_METHOD.CONFIRM };
  }

  private set(cards: readonly ProposalCard[]): void {
    this.current = cards;
    for (const listener of this.listeners) listener();
  }
}
