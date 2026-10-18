/**
 * What happened, one line a step, kept so "Copy what happened" can hand it over for support, as the
 * Mac's `Diary` does. Names and outcomes only, never what the person said or a command's arguments.
 */
export class Diary {
  private readonly lines: string[] = [];

  constructor(
    private readonly now: () => number = Date.now,
    /** Enough for the last few minutes of work, small enough to paste anywhere. */
    private readonly most = 400,
  ) {}

  note(line: string): void {
    this.lines.push(`${new Date(this.now()).toISOString()} ${line}`);
    if (this.lines.length > this.most) this.lines.splice(0, this.lines.length - this.most);
  }

  /** Every line kept, oldest first, headed so whoever reads it knows what it is. */
  text(about: string): string {
    return [`Memnox: what happened, ${about}`, ...this.lines].join('\n');
  }

  get count(): number {
    return this.lines.length;
  }
}
