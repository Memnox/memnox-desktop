import { INDEX_KIND, INDEX_METHOD, INDEX_SOURCE, type CommunityIndexView, type DaemonRequest, type DaemonResponse, type IndexEntryView } from '@memnox/core/wire';
import { INDEX_SOURCE_RESET, INDEX_SOURCE_SAME, indexInstalledLine, indexSourceProposedLine, type IndexKindFilter } from '../domain/index-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** How an Install ended: said in a line, since a skill only waits in My Skills and a pack only waits on the island. */
export type IndexOutcome = { kind: 'done'; note: string } | { kind: 'failed'; why: string };

/** How setting the source ended: another index waits on the island, the marketplace holds at once, or it was refused. */
export type IndexSourceOutcome = { kind: 'proposed'; note: string } | { kind: 'done'; note: string } | { kind: 'failed'; why: string };

/** What `busy` reads while the source is being set. */
export const SETTING_SOURCE = 'source';

/** What Discover asks the runtime for: words and a kind; the category is filtered by the window. */
export interface IndexFilter {
  readonly query: string;
  readonly kind: IndexKindFilter;
}

/**
 * The community index as the runtime reads it. Nothing here installs anything live: the runtime checks
 * the digest, a skill waits in My Skills for acceptance and a pack's rules each wait for a signature.
 */
export class CommunityIndex extends Observed {
  private view: CommunityIndexView | undefined;
  private packList: readonly IndexEntryView[] | undefined;
  private shown: IndexFilter = { query: '', kind: 'all' };
  private failed = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly keyTitle: string,
  ) {
    super();
  }

  get index(): CommunityIndexView | undefined {
    return this.view;
  }

  /** Rule packs alone, read for Governance > Policies without disturbing what Discover shows. */
  get packs(): readonly IndexEntryView[] | undefined {
    return this.packList;
  }

  get filter(): IndexFilter {
    return this.shown;
  }

  get unreadable(): boolean {
    return this.failed;
  }

  /** The listing an Install, or `refresh` for a fresh read, is still working on. */
  get busy(): string | undefined {
    return this.busyWith;
  }

  /** Reads with the filter given, or the one shown; `fresh` reads the index again rather than what was last read. */
  async refresh(filter: IndexFilter = this.shown, fresh = false): Promise<void> {
    this.shown = filter;
    if (fresh) this.busyWith = 'refresh';
    this.changed();
    const response = await this.ask({
      method: INDEX_METHOD.INDEX_LIST,
      ...(filter.query.trim() === '' ? {} : { indexQuery: filter.query.trim() }),
      ...(filter.kind === 'all' ? {} : { indexKind: filter.kind }),
      ...(fresh ? { indexRefresh: true } : {}),
    });
    if (fresh) this.busyWith = undefined;
    this.failed = response === undefined || !response.ok;
    if (response?.communityIndex !== undefined) this.view = response.communityIndex;
    this.changed();
  }

  async readPacks(): Promise<void> {
    const response = await this.ask({ method: INDEX_METHOD.INDEX_LIST, indexKind: INDEX_KIND.RULE_PACK });
    this.packList = response?.communityIndex?.entries ?? (response?.ok === true ? [] : undefined);
    this.changed();
  }

  /** Installs a version, or the newest not marked unsafe; the runtime refuses one marked unsafe either way. */
  async install(name: string, version?: string): Promise<IndexOutcome> {
    this.busyWith = name;
    this.changed();
    const response = await this.ask({ method: INDEX_METHOD.INDEX_INSTALL, indexName: name, ...(version === undefined ? {} : { indexVersion: version }) });
    this.busyWith = undefined;
    if (response?.communityIndex !== undefined) this.view = response.communityIndex;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.indexInstalled === undefined) return { kind: 'done', note: `${name} is installed.` };
    return { kind: 'done', note: indexInstalledLine(response.indexInstalled, this.keyTitle) };
  }

  /** Names another index, which only proposes it, or the marketplace when absent, which holds at once. */
  async setSource(address?: string): Promise<IndexSourceOutcome> {
    const source = address === undefined ? INDEX_SOURCE.MARKETPLACE : address.trim();
    this.busyWith = SETTING_SOURCE;
    this.changed();
    const response = await this.ask({ method: INDEX_METHOD.INDEX_SOURCE_SET, indexSource: source });
    this.busyWith = undefined;
    // The view still names the current source while a proposal waits, so it is taken as it came.
    if (response?.communityIndex !== undefined) this.view = response.communityIndex;
    this.changed();
    if (response === undefined) return { kind: 'failed', why: 'The runtime is not answering.' };
    if (!response.ok) return { kind: 'failed', why: response.error ?? 'The runtime refused this.' };
    if (response.proposed !== undefined) return { kind: 'proposed', note: indexSourceProposedLine(this.keyTitle) };
    return { kind: 'done', note: source === INDEX_SOURCE.MARKETPLACE ? INDEX_SOURCE_RESET : INDEX_SOURCE_SAME };
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes an index method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      // A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
      return undefined;
    }
  }
}
