import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import type { ConfirmKey } from '../src/core/application/ports/confirm-key';
import type { DaemonLink } from '../src/core/application/ports/daemon-link';

/** The daemon, scripted per method: each answer is a list of lines, and every request is kept. */
export class ScriptedDaemon implements DaemonLink {
  readonly requests: DaemonRequest[] = [];
  private readonly feed: DaemonEvent[] = [];

  constructor(private readonly answers: Partial<Record<string, (request: DaemonRequest) => DaemonResponse[]>> = {}) {}

  /** An event the live feed writes once it is open. */
  push(event: DaemonEvent): void {
    this.feed.push(event);
  }

  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    this.requests.push(request);
    const answer = this.answers[request.method];
    if (answer !== undefined) {
      yield* answer(request);
      return;
    }
    if (request.method !== 'subscribe') throw new Error(`nothing scripted for ${request.method}`);
    yield { id: request.id, ok: true };
    for (const event of this.feed.splice(0)) yield { id: request.id, ok: true, event };
  }

  sent(method: string): DaemonRequest[] {
    return this.requests.filter((request) => request.method === method);
  }
}

/**
 * A key that signs by naming the words, so a test reads what was signed. A null point is a computer
 * with no key, and `answers` false is the person cancelling the prompt.
 */
export class PersonKey implements ConfirmKey {
  readonly signed: { message: string; reason: string }[] = [];

  constructor(
    private readonly point: string | null = 'BPOINT',
    private readonly answers = true,
  ) {}

  publicPoint(): Promise<string | undefined> {
    return Promise.resolve(this.point ?? undefined);
  }

  sign(message: string, reason: string): Promise<string | undefined> {
    this.signed.push({ message, reason });
    return Promise.resolve(this.answers ? `sig(${message})` : undefined);
  }
}

export function held(subject: string, extra: Partial<DaemonEvent> = {}): DaemonEvent {
  return {
    kind: 'held',
    subject,
    agent: 'codex',
    summary: 'codex wants to push to main',
    what: 'push to main',
    at: '2026-10-17T10:00:00.000Z',
    ...extra,
  };
}

export const registered = (request: DaemonRequest): DaemonResponse[] => [
  { id: request.id, ok: true, outcome: 'registered' },
];
