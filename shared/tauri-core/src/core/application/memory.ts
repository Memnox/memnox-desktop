import { MEMORY_METHOD, type DaemonRequest, type DaemonResponse, type MemoryItemsView, type MemoryReadSummary, type MemorySourceInput, type MemorySourceView } from '@memnox/core/wire';
import { confirmedLine, readSummaryLine, type MemoryScopeName, type MemoryStatusName } from '../domain/memory-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How one press on memory ended: done at once, a rule waiting for its signature on the island, or refused. */
export type MemoryOutcome = { kind: 'done'; note: string } | { kind: 'proposed'; id: string; note: string } | { kind: 'failed'; why: string };

/** What the list shows: one status, one scope or both, or what a search found. */
export interface FactsFilter {
  readonly status: MemoryStatusName;
  readonly scope?: MemoryScopeName;
  /** Searched by keyword over every status when set. */
  readonly query?: string;
}

/**
 * Memory as the runtime keeps it: the sources a person pointed it at, the Learn queue read out of them, and
 * the facts a person confirmed. It holds no rule and no model: the runtime asks the person's own agent to
 * read, a confirm is the person's, and a rule a confirm raises waits for a signature on the island.
 */
export class Memory extends Observed {
  private sourceList: readonly MemorySourceView[] | undefined;
  private queue: MemoryItemsView | undefined;
  private listed: MemoryItemsView | undefined;
  private shown: FactsFilter = { status: 'verified' };
  private readonly reads = new Map<string, MemoryReadSummary>();
  private failed = { sources: false, learn: false, facts: false };
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  get sources(): readonly MemorySourceView[] | undefined {
    return this.sourceList;
  }

  get learn(): MemoryItemsView | undefined {
    return this.queue;
  }

  get facts(): MemoryItemsView | undefined {
    return this.listed;
  }

  get filter(): FactsFilter {
    return this.shown;
  }

  /** Which read failed, so each part of the page says its own. */
  get unreadable(): { readonly sources: boolean; readonly learn: boolean; readonly facts: boolean } {
    return this.failed;
  }

  /** The source or item a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  /** The last read of a source made here, said under its card. */
  lastRead(sourceId: string): MemoryReadSummary | undefined {
    return this.reads.get(sourceId);
  }

  async refreshSources(): Promise<void> {
    const response = await this.ask({ method: MEMORY_METHOD.MEMORY_SOURCES });
    this.failed = { ...this.failed, sources: response === undefined || !response.ok };
    this.take(response);
    this.changed();
  }

  async refreshLearn(): Promise<void> {
    const response = await this.ask({ method: MEMORY_METHOD.MEMORY_LEARN });
    this.failed = { ...this.failed, learn: response === undefined || !response.ok };
    this.take(response);
    this.changed();
  }

  /** Reads the list again under a filter, a search when it carries words. */
  async show(filter: FactsFilter): Promise<void> {
    this.shown = filter;
    const query = filter.query?.trim() ?? '';
    const scope = filter.scope === undefined ? {} : { memoryScope: filter.scope };
    const fields: Omit<DaemonRequest, 'id'> =
      query === '' ? { method: MEMORY_METHOD.MEMORY_FACTS, memoryStatus: filter.status, ...scope } : { method: MEMORY_METHOD.MEMORY_SEARCH, memoryQuery: query, ...scope };
    const response = await this.ask(fields);
    // A newer filter chosen while this one was asked wins.
    if (this.shown !== filter) return;
    this.failed = { ...this.failed, facts: response === undefined || !response.ok };
    this.listed = response?.memoryFacts ?? (response?.ok === true ? { items: [], more: 0 } : this.listed);
    this.changed();
  }

  /** Kept at once; the runtime reads it in the background, so what it taught arrives on the next look. */
  addSource(input: MemorySourceInput): Promise<MemoryOutcome> {
    return this.change('add', { method: MEMORY_METHOD.MEMORY_SOURCE_ADD, memorySource: input }, () => 'Added. Memnox is reading it now, and what it finds waits in Learn.');
  }

  removeSource(id: string): Promise<MemoryOutcome> {
    return this.change(id, { method: MEMORY_METHOD.MEMORY_SOURCE_REMOVE, memorySourceId: id }, () => 'Removed. What it taught is kept as outdated rather than lost.');
  }

  readNow(id: string): Promise<MemoryOutcome> {
    return this.change(id, { method: MEMORY_METHOD.MEMORY_SOURCE_READ, memorySourceId: id }, (response) => {
      const summary = response.memoryRead;
      if (summary === undefined) return 'Read.';
      this.reads.set(id, summary);
      return readSummaryLine(summary);
    });
  }

  confirm(id: string, keyTitle: string): Promise<MemoryOutcome> {
    return this.change(id, { method: MEMORY_METHOD.MEMORY_CONFIRM, memoryItemId: id }, (response) =>
      confirmedLine(response.memoryItem?.kind ?? 'fact', response.proposed !== undefined, keyTitle),
    );
  }

  reject(id: string): Promise<MemoryOutcome> {
    return this.change(id, { method: MEMORY_METHOD.MEMORY_REJECT, memoryItemId: id }, () => 'Rejected. The same words are never proposed again.');
  }

  /** New words before it is confirmed, kept exactly as typed. */
  edit(id: string, statement: string): Promise<MemoryOutcome> {
    return this.change(id, { method: MEMORY_METHOD.MEMORY_EDIT, memoryItemId: id, memoryEdit: { statement } }, () => 'Saved. Confirm it when it says what you mean.');
  }

  async forget(id: string): Promise<MemoryOutcome> {
    const outcome = await this.change(id, { method: MEMORY_METHOD.MEMORY_FORGET, memoryItemId: id }, () => 'Forgotten, with its evidence.');
    if (outcome.kind === 'done' && this.listed !== undefined) {
      this.listed = { ...this.listed, items: this.listed.items.filter((item) => item.id !== id) };
      this.changed();
    }
    return outcome;
  }

  private take(response: DaemonResponse | undefined): void {
    if (response?.memorySources !== undefined) this.sourceList = response.memorySources;
    if (response?.memoryLearn !== undefined) this.queue = response.memoryLearn;
  }

  private async change(subject: string, fields: Omit<DaemonRequest, 'id'>, done: (response: DaemonResponse) => string): Promise<MemoryOutcome> {
    this.busyWith = subject;
    this.changed();
    const response = await this.ask(fields);
    this.busyWith = undefined;
    this.take(response);
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    const note = done(response);
    if (response.proposed !== undefined) return { kind: 'proposed', id: response.proposed, note };
    return { kind: 'done', note };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a memory method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
