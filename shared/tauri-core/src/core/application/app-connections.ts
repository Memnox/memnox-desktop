import { DAEMON_METHOD, type DaemonRequest, type DaemonResponse, type ToolConnection } from '@memnox/core/wire';
import { toolkitName } from '../domain/tool-brand';
import { Observed, type Sleep } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { Timer } from './talking';
import type { Tools } from './tools';

/** One tool Memnox Cloud's catalogue offers, by the slug connections-sign-in takes. */
export type ToolkitSummary = NonNullable<DaemonResponse['toolkits']>[number];

/** Where adding, signing in again and disconnecting stand, for the Apps card and its search. */
export interface AppConnectionsState {
  /** The tool being signed in to or disconnected, so its row waits rather than taking a second press. */
  readonly busy: string | undefined;
  /** The daemon's own words for the last thing it refused, shown on the Apps card until the next try. */
  readonly note: string | undefined;
  /** The tool whose sign in is open in the browser, read again until it shows up. */
  readonly waitingFor: string | undefined;
  readonly query: string;
  readonly found: readonly ToolkitSummary[];
  /** Why the catalogue could not be searched, in the daemon's words. */
  readonly searchNote: string | undefined;
  readonly searching: boolean;
}

/** Said when the daemon does not answer at all. */
const UNREACHABLE = 'Memnox is not running';
/** Said for a daemon that answers a method it does not know with a bare ok. */
const OLDER = 'This Memnox is older than the app';
/** Long enough to let a word be finished before the catalogue is asked, short enough to feel live. */
export const TYPING_PAUSE_MS = 300;
/** How often the list is read while the browser sign in is under way, as the Mac's `watchInterval`. */
export const WATCH_INTERVAL_MS = 3_000;
/** Two minutes of reads, long enough for a sign in with a second factor and short enough to stop for one abandoned. */
export const WATCH_READS = 40;

/**
 * Connects any tool the person uses and disconnects it again, with no admin in between, ported from the
 * Mac's `AppConnections` and `ToolsModel`: the daemon holds the sign in and the cloud keeps it, so this
 * only carries the person's wish and reads the list back through `Tools`, which every screen shows.
 */
export class AppConnections extends Observed {
  private current: AppConnectionsState = {
    busy: undefined,
    note: undefined,
    waitingFor: undefined,
    query: '',
    found: [],
    searchNote: undefined,
    searching: false,
  };
  private cancelSearch: (() => void) | undefined;
  /** Bumped by every search, so an answer that a newer search overtook is dropped. */
  private searchTurn = 0;
  private watchTurn = 0;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly tools: Tools,
    /** Opens a sign in page the daemon could not open itself, as on a server across the relay. */
    private readonly open: (url: string) => void,
    private readonly sleep: Sleep,
    /** The search after typing pauses waits on this, handed in since the core has no clock of its own. */
    private readonly timer: Timer,
  ) {
    super();
  }

  get state(): AppConnectionsState {
    return this.current;
  }

  /** Takes the typed words and asks the catalogue once typing pauses; a newer search replaces one still waiting. */
  search(query: string): void {
    this.cancelSearch?.();
    const turn = ++this.searchTurn;
    this.set({ query, searching: true });
    this.cancelSearch = this.timer(TYPING_PAUSE_MS, () => void this.lookUp(query, turn));
  }

  /** Starts the tool's own sign in; again opens a fresh one for a tool that already has one, to use another account. */
  async connect(toolkit: string, again = false): Promise<void> {
    if (this.current.busy !== undefined) return;
    this.set({ busy: toolkit, note: undefined });
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.CONNECTIONS_SIGN_IN, toolkit, ...(again ? { again: true } : {}) });
    this.set({ busy: undefined });
    if (response === undefined) return this.set({ note: UNREACHABLE });
    if (!response.ok || response.signIn === undefined) return this.set({ note: refusal(response) });
    // The daemon opens the page itself over this computer's socket; only a server's answer is left to open here.
    if (!response.signIn.opened) {
      if (!response.signIn.url.startsWith('https://')) return this.set({ note: `The browser would not open the ${toolkitName(toolkit)} sign in` });
      this.open(response.signIn.url);
    }
    await this.watch(toolkit);
  }

  /** Takes the tool's sign in away and shows the list the daemon answers with. */
  async disconnect(toolkit: string): Promise<void> {
    if (this.current.busy !== undefined) return;
    this.set({ busy: toolkit, note: undefined });
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.CONNECTIONS_SIGN_OUT, toolkit });
    this.set({ busy: undefined });
    if (response === undefined) return this.set({ note: UNREACHABLE });
    if (!response.ok || response.connections === undefined) return this.set({ note: refusal(response) });
    this.tools.useConnections(response.connections);
  }

  /** Reads the list while the person finishes in the browser, until it differs from the one before or time runs out. */
  private async watch(toolkit: string): Promise<void> {
    const turn = ++this.watchTurn;
    const before = this.tools.state.connections;
    this.set({ waitingFor: toolkit });
    for (let read = 0; read < WATCH_READS; read += 1) {
      await this.sleep(WATCH_INTERVAL_MS);
      if (turn !== this.watchTurn) return;
      await this.tools.refresh();
      if (!sameConnections(before, this.tools.state.connections)) break;
    }
    if (turn === this.watchTurn) this.set({ waitingFor: undefined });
  }

  private async lookUp(query: string, turn: number): Promise<void> {
    const words = query.trim();
    const response = await this.ask({ id: this.ids.next(), method: DAEMON_METHOD.TOOLKITS_SEARCH, ...(words === '' ? {} : { query: words }) });
    if (turn !== this.searchTurn) return;
    if (response === undefined) return this.set({ found: [], searchNote: UNREACHABLE, searching: false });
    if (!response.ok || response.toolkits === undefined) return this.set({ found: [], searchNote: refusal(response), searching: false });
    this.set({ found: response.toolkits, searchNote: undefined, searching: false });
  }

  private ask(request: DaemonRequest): Promise<DaemonResponse | undefined> {
    return requestOnce(this.link, request).catch(() => undefined);
  }

  private set(next: Partial<AppConnectionsState>): void {
    this.current = { ...this.current, ...next };
    this.changed();
  }
}

function refusal(response: DaemonResponse): string {
  return response.error ?? response.reason ?? OLDER;
}

function sameConnections(a: readonly ToolConnection[], b: readonly ToolConnection[]): boolean {
  return a.length === b.length && a.every((each, index) => each.toolkit === b[index]?.toolkit && each.connected === b[index]?.connected);
}
