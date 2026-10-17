/** One call waiting on the person, and the machine it waits on. */
export interface WaitingEntry<Card> {
  readonly subject: string;
  readonly machine: string;
  readonly card: Card;
}

/**
 * Every held call waiting on the person, so a second one joins the first rather than taking its
 * place unseen. The newest comes on screen unless the person stepped to another. Ported from the
 * Mac's `WaitingCalls`, and immutable so a screen can compare one state with the next.
 */
export class WaitingCalls<Card> {
  private constructor(
    /** Oldest first, in the order they arrived. */
    readonly entries: readonly WaitingEntry<Card>[],
    readonly shownSubject: string | undefined,
    /** Set once the person stepped to a call, so one arriving never moves the card from under their hand. */
    private readonly steppedTo: boolean,
  ) {}

  static empty<Card>(): WaitingCalls<Card> {
    return new WaitingCalls<Card>([], undefined, false);
  }

  get count(): number {
    return this.entries.length;
  }

  get shown(): WaitingEntry<Card> | undefined {
    return this.entries.find((entry) => entry.subject === this.shownSubject);
  }

  /** Newest first, the order the person steps through them in. */
  get newestFirst(): WaitingEntry<Card>[] {
    return [...this.entries].reverse();
  }

  /** A call that started waiting; one told again, as on a reconnect, keeps its place in the queue. */
  add(card: Card, subject: string, machine: string, keepShown = false): WaitingCalls<Card> {
    const entry = { subject, machine, card };
    const at = this.entries.findIndex((each) => each.subject === subject);
    if (at !== -1) {
      const entries = this.entries.map((each, index) => (index === at ? entry : each));
      return new WaitingCalls(entries, this.shownSubject, this.steppedTo);
    }
    const moves = this.shownSubject === undefined || !(this.steppedTo || keepShown);
    return new WaitingCalls([...this.entries, entry], moves ? subject : this.shownSubject, this.steppedTo);
  }

  /** A call that stopped waiting; the newest left comes up when it was the one shown. */
  remove(subject: string): WaitingCalls<Card> {
    const entries = this.entries.filter((each) => each.subject !== subject);
    if (entries.length === this.entries.length) return this;
    if (this.shownSubject !== subject) return new WaitingCalls(entries, this.shownSubject, this.steppedTo);
    return new WaitingCalls(entries, entries[entries.length - 1]?.subject, false);
  }

  has(subject: string): boolean {
    return this.entries.some((entry) => entry.subject === subject);
  }

  /** Where the shown call stands, counted from the newest as one. */
  get position(): number | undefined {
    const at = this.newestFirst.findIndex((entry) => entry.subject === this.shownSubject);
    return at === -1 ? undefined : at + 1;
  }

  get canStepOlder(): boolean {
    return (this.position ?? this.count) < this.count;
  }

  get canStepNewer(): boolean {
    return (this.position ?? 1) > 1;
  }

  /** One call older for a positive offset, newer for a negative one, stopping at either end. */
  step(offset: number): WaitingCalls<Card> {
    const order = this.newestFirst;
    const position = this.position;
    if (position === undefined || order.length === 0) return this;
    const next = Math.min(Math.max(position - 1 + offset, 0), order.length - 1);
    if (next === position - 1) return this;
    return new WaitingCalls(this.entries, order[next]?.subject, true);
  }

  /** "2 of 3", undefined while only one waits. */
  get positionText(): string | undefined {
    const position = this.position;
    if (this.count < 2 || position === undefined) return undefined;
    return `${position} of ${this.count}`;
  }

  /** "3 waiting: 2 on build-box, 1 on this computer"; the machine with the most first, ties to the latest. */
  get header(): string | undefined {
    if (this.count < 2) return undefined;
    const groups: { machine: string; count: number; newest: number }[] = [];
    this.entries.forEach((entry, order) => {
      const group = groups.find((each) => each.machine === entry.machine);
      if (group === undefined) groups.push({ machine: entry.machine, count: 1, newest: order });
      else {
        group.count += 1;
        group.newest = order;
      }
    });
    const [only] = groups;
    if (groups.length === 1 && only !== undefined) return `${this.count} waiting on ${only.machine}`;
    const sorted = groups.sort((a, b) => b.count - a.count || b.newest - a.newest);
    return `${this.count} waiting: ${sorted.map((each) => `${each.count} on ${each.machine}`).join(', ')}`;
  }
}
