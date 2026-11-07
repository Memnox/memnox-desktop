import { MEMORY_METHOD, type DaemonRequest, type DaemonResponse, type MemoryItemsView, type MemoryReadSummary, type MemorySearchMode, type MemorySourceInput, type MemorySourceView } from '@memnox/core/wire';
import { confirmedLine, readSummaryLine, type MemoryScopeName, type MemoryStatusName } from '../domain/memory-lines';
import { writtenLine, type MemoryLayersPlan, type MemoryLayersView, type SessionCostView } from '../domain/memory-layers-lines';
import type { WorkspaceGraphView } from '../domain/memory-arms/arms-local';
import type { MemoryItemView } from '@memnox/core/wire';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How one press on memory ended: done at once, a rule waiting for its signature on the island, or refused. */
export type MemoryOutcome = { kind: 'done'; note: string } | { kind: 'proposed'; id: string; note: string } | { kind: 'failed'; why: string };

/** Every status an item can be in, the chips' order first, so a reopened item is found wherever it went. */
const EVERY_STATUS: readonly MemoryStatusName[] = ['verified', 'candidate', 'conflicting', 'outdated', 'rejected', 'superseded'];

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
  private searched: { readonly mode: MemorySearchMode; readonly note?: string } | undefined;
  private readonly reads = new Map<string, MemoryReadSummary>();
  private failed = { sources: false, learn: false, facts: false };
  private busyWith: string | undefined;
  private layersRead: MemoryLayersView | undefined;
  private layersFailed = false;
  private planShown: { readonly plan: MemoryLayersPlan; readonly project: string; readonly agent?: string; readonly keep: readonly string[] } | undefined;
  private costRead: SessionCostView | undefined;
  private graphRead: WorkspaceGraphView | undefined;
  private everyRead: readonly MemoryItemView[] | undefined;

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

  /** How the last search was answered, by keyword or by meaning, and why it fell back; undefined when the list is no search. */
  get search(): { readonly mode: MemorySearchMode; readonly note?: string } | undefined {
    return this.searched;
  }

  /** Which read failed, so each part of the page says its own. */
  get unreadable(): { readonly sources: boolean; readonly learn: boolean; readonly facts: boolean } {
    return this.failed;
  }

  /** The source or item a press is still working on, so its controls can say so. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  /** Each project's three layers as they stand, and what memory measured about itself. */
  get layers(): MemoryLayersView | undefined {
    return this.layersRead;
  }

  /** The last layers read failed, or came from a runtime too old to answer it. */
  get layersUnreadable(): boolean {
    return this.layersFailed;
  }

  /** The map the runtime would write, shown until it is confirmed or put away. */
  get plan(): MemoryLayersPlan | undefined {
    return this.planShown?.plan;
  }

  /** How often a cold cache was loaded again lately, counted from the chats alone. */
  get sessionCost(): SessionCostView | undefined {
    return this.costRead;
  }

  /** What the workspace settled and what its tools said, live or as this computer last saved it. */
  get workspaceGraph(): WorkspaceGraphView | undefined {
    return this.graphRead;
  }

  /** Every item memory holds whatever its status, for the brain, which keeps history faintly on the picture. */
  get everything(): readonly MemoryItemView[] | undefined {
    return this.everyRead;
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
    this.searched = searchOf(query, response);
    this.changed();
  }

  /**
   * Finds which status holds an item, list by list, since the runtime reads none by id: a popped out item
   * reopens whatever became of it. Leaves that list shown and says its status, or undefined when no list holds it.
   */
  async reveal(id: string): Promise<MemoryStatusName | undefined> {
    if (this.listed !== undefined && this.listed.items.some((item) => item.id === id)) return this.shown.status;
    for (const status of EVERY_STATUS) {
      const filter: FactsFilter = { status };
      const response = await this.ask({ method: MEMORY_METHOD.MEMORY_FACTS, memoryStatus: status });
      const found = response?.memoryFacts;
      if (found === undefined || !found.items.some((item) => item.id === id)) continue;
      this.shown = filter;
      this.listed = found;
      this.searched = undefined;
      this.changed();
      return status;
    }
    return undefined;
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

  /** Reads the layers and the cold cache count; a runtime that answers neither leaves the view saying so. */
  async refreshLayers(): Promise<void> {
    const [layers, cost] = await Promise.all([this.ask({ method: MEMORY_METHOD.MEMORY_LAYERS }), this.ask({ method: MEMORY_METHOD.SESSION_COST })]);
    this.layersFailed = layers?.ok !== true || layers.memoryLayers === undefined;
    if (layers?.memoryLayers !== undefined) this.layersRead = layers.memoryLayers;
    if (cost?.sessionCost !== undefined) this.costRead = cost.sessionCost;
    this.changed();
  }

  /** Asks the runtime for the map it would write; nothing is written by this. Undefined when the plan is shown. */
  async previewLayers(project: string, keep: readonly string[], agent?: string): Promise<string | undefined> {
    const response = await this.working(project, () =>
      this.ask({ method: MEMORY_METHOD.MEMORY_LAYERS_PLAN, memoryLayersProject: project, memoryKeep: [...keep], ...(agent === undefined ? {} : { memoryLayersAgent: agent }) }),
    );
    if (response === undefined) return 'The runtime is not answering.';
    if (!response.ok || response.memoryLayersPlan === undefined) return response.error ?? 'The runtime could not plan the layers.';
    this.planShown = { plan: response.memoryLayersPlan, project, keep, ...(agent === undefined ? {} : { agent }) };
    this.changed();
    return undefined;
  }

  /** Writes the plan the person confirmed, with its digest, so a plan whose files changed since is refused. */
  async confirmLayers(): Promise<MemoryOutcome> {
    const shown = this.planShown;
    if (shown === undefined) return { kind: 'failed', why: 'There is no plan to confirm.' };
    const response = await this.working(shown.project, () =>
      this.ask({
        method: MEMORY_METHOD.MEMORY_LAYERS_APPLY,
        memoryLayersProject: shown.project,
        memoryKeep: [...shown.keep],
        memoryLayersDigest: shown.plan.digest,
        ...(shown.agent === undefined ? {} : { memoryLayersAgent: shown.agent }),
      }),
    );
    this.planShown = undefined;
    if (response === undefined) {
      this.changed();
      return { kind: 'failed', why: 'The runtime is not answering.' };
    }
    if (!response.ok) {
      this.changed();
      return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    }
    const updated = response.memoryLayers;
    if (updated !== undefined) {
      // One project read again after apply, laid over the rest.
      const fresh = new Map(updated.projects.map((project) => [project.path, project]));
      this.layersRead = this.layersRead === undefined ? updated : { projects: this.layersRead.projects.map((project) => fresh.get(project.path) ?? project), value: updated.value };
    }
    this.changed();
    return { kind: 'done', note: writtenLine(response.memoryLayersApplied?.written ?? []) };
  }

  /** The sheet closed without confirming, so the plan is forgotten. */
  dismissPlan(): void {
    this.planShown = undefined;
    this.changed();
  }

  /** The workspace's graph, read again from the cloud when `fresh`; always answered, saved where the cloud did not. */
  async refreshWorkspaceGraph(fresh = false): Promise<void> {
    const response = await this.ask({ method: MEMORY_METHOD.WORKSPACE_GRAPH, ...(fresh ? { workspaceGraphFresh: true } : {}) });
    if (response?.workspaceGraph !== undefined) this.graphRead = response.workspaceGraph;
    this.changed();
  }

  /** Every status read at once, so the brain holds the whole record rather than the list's one filter. */
  async refreshEverything(): Promise<void> {
    const reads = await Promise.all(EVERY_STATUS.map((status) => this.ask({ method: MEMORY_METHOD.MEMORY_FACTS, memoryStatus: status })));
    if (reads.every((response) => response?.memoryFacts === undefined)) return;
    this.everyRead = reads.flatMap((response) => response?.memoryFacts?.items ?? []);
    this.changed();
  }

  private async working<T>(subject: string, body: () => Promise<T>): Promise<T> {
    this.busyWith = subject;
    this.changed();
    const result = await body();
    this.busyWith = undefined;
    this.changed();
    return result;
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

/** How a search was answered, as the runtime says it; an older runtime that names no mode searched by keyword. */
function searchOf(query: string, response: DaemonResponse | undefined): { mode: MemorySearchMode; note?: string } | undefined {
  if (query === '' || response === undefined || !response.ok) return undefined;
  const mode = response.memorySearchMode ?? 'keyword';
  return response.memorySearchNote === undefined ? { mode } : { mode, note: response.memorySearchNote };
}
