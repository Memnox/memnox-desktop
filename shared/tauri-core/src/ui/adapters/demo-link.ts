import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import type { DaemonLink } from '../../core/application/ports/daemon-link';

/** A JSON value from the demo world. */
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type Fields = { [key: string]: Json };

/** The demo world as `shared/demo/power-user.json` writes it, the same file the Mac's `DemoLink` reads. */
export interface DemoWorld {
  readonly demoOnly: string;
  readonly answers: Record<string, Fields>;
  readonly writes: Record<string, string>;
  readonly held: Fields[];
  readonly notices: Fields[];
  readonly sessionViews: Record<string, Fields>;
  readonly memory: Fields[];
}

const UNIT_SECONDS: Record<string, number> = { s: 1, m: 60, h: 3_600, d: 86_400 };
const MARKER = /^\$now(?:([+-])(\d+(?:\.\d+)?)([smhd]))?$/;

/** A time written as the daemon writes it, to the second. */
export function isoSecond(at: Date): string {
  return at.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** The time a `$now-5m` marker names, or undefined when the text is not one. Ported from the Mac's `DemoTime`. */
export function demoStamp(text: string, now: Date): string | undefined {
  const marker = MARKER.exec(text);
  if (marker === null) return undefined;
  const [, sign, amount, unit] = marker;
  const seconds = sign === undefined ? 0 : Number(amount) * (UNIT_SECONDS[unit ?? 's'] ?? 0) * (sign === '-' ? -1 : 1);
  return isoSecond(new Date(now.getTime() + seconds * 1_000));
}

function stamped(value: Json, now: Date): Json {
  if (typeof value === 'string') return demoStamp(value, now) ?? value;
  if (Array.isArray(value)) return value.map((each) => stamped(each, now));
  if (value !== null && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, each]) => [key, stamped(each, now)]));
  return value;
}

const text = (value: Json | undefined): string | undefined => (typeof value === 'string' ? value : undefined);
const items = (list: Fields[]) => ({ items: list, more: 0 });
const OPEN_MEMORY = new Set(['candidate', 'conflicting']);

/**
 * A daemon made of the demo world, so every page draws full for a person judging the design. Nothing reaches the
 * real daemon: reads come from the fixture, a held call answered is settled here alone, a write answers with its page
 * as it stood, and what only a daemon can do says it is demo data. Ported from the Mac's `DemoLink`.
 */
export class DemoLink implements DaemonLink {
  private readonly world: DemoWorld;
  private readonly settled = new Set<string>();
  private readonly listeners = new Set<(response: DaemonResponse) => void>();

  constructor(fixture: unknown, private readonly now: () => Date = () => new Date()) {
    this.world = stamped(fixture as Json, now()) as unknown as DemoWorld;
  }

  /** The person the demo is signed in as. */
  get personName(): string {
    return text((this.world.answers['person']?.['person'] as Fields | undefined)?.['name']) ?? '';
  }

  get demoOnly(): string {
    return this.world.demoOnly;
  }

  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    if (request.method === 'subscribe') {
      yield* this.listen();
      return;
    }
    if (request.method === 'confirm' && request.subject !== undefined) this.settle(request.subject);
    for (const line of this.answers(request)) yield { ...line, id: request.id } as unknown as DaemonResponse;
  }

  private answers(request: DaemonRequest): Fields[] {
    const ok = { ok: true };
    const { answers, writes } = this.world;
    switch (request.method) {
      case 'waiting':
        return [{ ...ok, waiting: this.waiting() }];
      case 'home': {
        const home = answers['home']?.['home'] as Fields | undefined;
        return [home === undefined ? ok : { ...ok, home: { ...home, waiting: this.waiting().length } }];
      }
      case 'session-view':
        return [{ ...ok, session: this.sessionView(request.sessionId) }];
      case 'activity':
        return [{ ...ok, activity: { rows: this.activity(request.activityFilter) } }];
      case 'decision':
        return [this.decision(request.decisionId)];
      case 'memory-facts':
        return [{ ...ok, memoryFacts: items(this.world.memory.filter((item) => item['status'] === (request.memoryStatus ?? 'verified') && this.inScope(item, request.memoryScope))) }];
      case 'memory-search': {
        const words = (request.memoryQuery ?? '').toLowerCase();
        return [{ ...ok, memoryFacts: items(this.world.memory.filter((item) => (text(item['statement']) ?? '').toLowerCase().includes(words) && this.inScope(item, request.memoryScope))) }];
      }
      case 'memory-learn':
      case 'memory-reject':
      case 'memory-edit':
        return [{ ...ok, memoryLearn: items(this.learn()) }];
      case 'memory-confirm': {
        const item = this.world.memory.find((each) => each['id'] === request.memoryItemId);
        return [{ ...ok, memoryLearn: items(this.learn()), ...(item === undefined ? {} : { memoryItem: item }) }];
      }
      case 'ask':
        return [{ ...ok, chunk: { kind: 'text', text: this.world.demoOnly } }, { ...ok, chunk: { kind: 'done' } }];
      default: {
        const page = writes[request.method];
        return [answers[request.method] ?? (page === undefined ? undefined : answers[page]) ?? ok];
      }
    }
  }

  /** Held calls and notices as a subscription opens with them, then kept open so an answer here settles its card. */
  private async *listen(): AsyncIterable<DaemonResponse> {
    // Listening starts before the opening events go out, so an answer pressed while they are read is not missed.
    const queue: DaemonResponse[] = [...this.waiting(), ...this.world.notices].map((event) => ({ id: 0, ok: true, event }) as unknown as DaemonResponse);
    let wake: (() => void) | undefined;
    const hear = (response: DaemonResponse) => {
      queue.push(response);
      wake?.();
    };
    this.listeners.add(hear);
    try {
      while (true) {
        const next = queue.shift();
        if (next !== undefined) {
          yield next;
          continue;
        }
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
        wake = undefined;
      }
    } finally {
      this.listeners.delete(hear);
    }
  }

  private settle(subject: string): void {
    const call = this.world.held.find((each) => each['subject'] === subject);
    if (call === undefined) return;
    this.settled.add(subject);
    const event = { kind: 'settled', subject, agent: call['agent'] ?? '', summary: call['summary'] ?? '', at: isoSecond(this.now()) };
    for (const listener of this.listeners) listener({ id: 0, ok: true, event } as unknown as DaemonResponse);
  }

  private waiting(): Fields[] {
    return this.world.held.filter((each) => !this.settled.has(text(each['subject']) ?? ''));
  }

  private sessionView(id: string | undefined): Fields | null {
    const views = this.world.sessionViews;
    const first = Object.keys(views).sort()[0];
    return (id === undefined ? undefined : views[id]) ?? (first === undefined ? undefined : views[first]) ?? null;
  }

  private rows(): Fields[] {
    return (((this.world.answers['activity']?.['activity'] as Fields | undefined)?.['rows'] ?? []) as Fields[]);
  }

  /** The ledger narrowed as Activity and Today ask for it, by effect, agent, kind, words and time. */
  private activity(filter: DaemonRequest['activityFilter']): Fields[] {
    if (filter === undefined) return this.rows();
    const since = filter.since === undefined ? undefined : Date.parse(filter.since);
    const until = filter.until === undefined ? undefined : Date.parse(filter.until);
    const words = filter.text?.toLowerCase();
    return this.rows().filter((row) => {
      if (filter.effect !== undefined && row['effect'] !== filter.effect) return false;
      if (filter.agent !== undefined && row['agent'] !== filter.agent) return false;
      if (filter.kind !== undefined && row['kind'] !== filter.kind) return false;
      if (words !== undefined && words !== '') {
        const haystack = ['operation', 'target', 'rule'].map((key) => text(row[key]) ?? '').join(' ').toLowerCase();
        if (!haystack.includes(words)) return false;
      }
      const at = Date.parse(text(row['at']) ?? '');
      if (since !== undefined && at < since) return false;
      if (until !== undefined && at > until) return false;
      return true;
    });
  }

  /** Why one ledger row went the way it did, built from the row itself. */
  private decision(id: string | undefined): Fields {
    const row = this.rows().find((each) => each['id'] === id) ?? this.rows()[0];
    if (row === undefined) return { ok: true };
    const rule = text(row['rule']);
    const task = this.world.sessionViews[text(row['session']) ?? '']?.['task'];
    return {
      ok: true,
      decision: {
        row,
        chain: `${text(row['agentName']) ?? ''} for ${this.personName}`,
        context: [],
        before: [],
        trace: { mode: 'shell', exitCode: 0, durationMs: 840 },
        ...(rule === undefined ? {} : { rule: { name: rule, source: 'person', decidedBy: this.personName } }),
        ...(task === undefined ? {} : { task }),
      },
    };
  }

  private inScope(item: Fields, scope: string | undefined): boolean {
    return scope === undefined || item['scope'] === scope;
  }

  /** What waits to be learned: the candidates and the conflicts. */
  private learn(): Fields[] {
    return this.world.memory.filter((item) => OPEN_MEMORY.has(text(item['status']) ?? ''));
  }
}
