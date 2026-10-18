import type { PhoneTurn } from '@memnox/core/wire';
import type { Exchange } from './history';

/** One turn of a phone's conversation as the island shows it: which phone, what was said, the answer so far. */
export interface PhoneExchange {
  readonly id: string;
  readonly deviceId: string;
  /** "From Ana's iPhone", with a plain word when the phone gave no name. */
  readonly label: string;
  /** The same turn as the answer card reads one, so a phone's turn looks like the person's own. */
  readonly exchange: Exchange;
}

function words(text: string | undefined): string | undefined {
  return text === undefined || text.trim() === '' ? undefined : text;
}

/**
 * Puts a phone's turn together from the notices the daemon mirrors: said starts one, answer chunks add
 * to it, and ended closes it. Only the newest turn is kept, since the island shows one at a time.
 * Ported from the Mac's `PhoneConversation`.
 */
export class PhoneConversation {
  private turn: PhoneExchange | undefined;
  private made = 0;

  get current(): PhoneExchange | undefined {
    return this.turn;
  }

  /** The turn as it stands after this notice, or undefined when the notice changed nothing worth showing. */
  take(notice: PhoneTurn, at: number): PhoneExchange | undefined {
    const said = words(notice.said);
    const chunk = notice.answer === undefined || notice.answer === '' ? undefined : notice.answer;
    const open = this.turn !== undefined && this.turn.deviceId === notice.deviceId && this.turn.exchange.answeredAt === undefined ? this.turn : undefined;
    let next: PhoneExchange;
    if (said !== undefined || (open === undefined && chunk !== undefined)) {
      // A start that was missed still shows the answer, under no question.
      this.made += 1;
      const name = notice.name.trim();
      next = { id: `phn_${at}_${this.made}`, deviceId: notice.deviceId, label: `From ${name === '' ? 'your phone' : name}`, exchange: { id: `phn_${at}_${this.made}`, question: said ?? '', answer: '', askedAt: at } };
    } else if (open !== undefined) {
      next = open;
    } else {
      return undefined;
    }
    if (chunk !== undefined) next = { ...next, exchange: { ...next.exchange, answer: next.exchange.answer + chunk } };
    if (notice.ended === true && next.exchange.answeredAt === undefined) next = { ...next, exchange: { ...next.exchange, answeredAt: at } };
    if (next === this.turn) return undefined;
    this.turn = next;
    return next;
  }
}
