import type { Platform } from '../domain/platform';
import { newestAppRelease, newestRuntimeVersion, offered, type UpdateKind, type UpdateOffer } from '../domain/updates';
import { Observed } from './observed';
import type { ReleaseFeed } from './ports/release-feed';

/** What the use case needs of the app around it, each read when asked so a test answers as it likes. */
export interface UpdateFacts {
  readonly platform: Platform;
  /** The version of the app running, or undefined in a preview, which is offered nothing. */
  appVersion(): Promise<string | undefined>;
  /** The version the service answers with, or undefined while it is away or built from a checkout. */
  runtimeVersion(): Promise<string | undefined>;
  /** The version of each kind the person put off. */
  skipped(kind: UpdateKind): string | undefined;
  putOff(kind: UpdateKind, version: string): void;
  /** Updates the service in place: undefined once it answers again, else why not. */
  updateRuntime(): Promise<string | undefined>;
  openPage(url: string): void;
}

/**
 * A newer app or a newer Memnox service, offered until the person updates or presses Later, as the Mac's
 * `AppUpdates`. The app is fetched in the browser, since each system installs it its own way; the service is
 * updated in place by the same step setup takes for one too old.
 */
export class Updates extends Observed {
  private found: readonly UpdateOffer[] = [];
  private working: UpdateKind | undefined;
  private why: string | undefined;

  constructor(
    private readonly feed: ReleaseFeed | undefined,
    private readonly facts: UpdateFacts,
  ) {
    super();
  }

  get offers(): readonly UpdateOffer[] {
    return this.found;
  }

  /** The kind being updated now, so its button cannot be pressed twice. */
  get busy(): UpdateKind | undefined {
    return this.working;
  }

  /** Why the last update stopped short, until the next press. */
  get failed(): string | undefined {
    return this.why;
  }

  /** Reads both lists and keeps what is worth offering; a list that could not be read offers nothing. */
  async look(): Promise<void> {
    if (this.feed === undefined) return;
    const [app, runtime] = await Promise.all([this.appOffer(this.feed), this.runtimeOffer(this.feed)]);
    this.found = [app, runtime].filter((offer): offer is UpdateOffer => offer !== undefined);
    this.changed();
  }

  private async appOffer(feed: ReleaseFeed): Promise<UpdateOffer | undefined> {
    const running = await this.facts.appVersion().catch(() => undefined);
    if (running === undefined) return undefined;
    const body = await feed.read('app').catch(() => undefined);
    const newest = body === undefined ? undefined : newestAppRelease(body, this.facts.platform);
    if (newest === undefined || !offered(newest.version, running, this.facts.skipped('app'))) return undefined;
    return { kind: 'app', version: newest.version, url: newest.url };
  }

  private async runtimeOffer(feed: ReleaseFeed): Promise<UpdateOffer | undefined> {
    const running = await this.facts.runtimeVersion().catch(() => undefined);
    if (running === undefined) return undefined;
    const body = await feed.read('runtime').catch(() => undefined);
    const newest = body === undefined ? undefined : newestRuntimeVersion(body);
    return offered(newest, running, this.facts.skipped('runtime')) && newest !== undefined ? { kind: 'runtime', version: newest } : undefined;
  }

  /** The offer's press: the app's installer opens in the browser, and the service is updated here and now. */
  async update(offer: UpdateOffer): Promise<void> {
    if (this.working !== undefined) return;
    this.why = undefined;
    if (offer.kind === 'app') {
      if (offer.url !== undefined) this.facts.openPage(offer.url);
      this.changed();
      return;
    }
    this.working = 'runtime';
    this.changed();
    this.why = await this.facts.updateRuntime().catch((error: unknown) => String(error));
    this.working = undefined;
    if (this.why === undefined) this.found = this.found.filter((each) => each.kind !== 'runtime');
    this.changed();
  }

  /** Later: this version is not offered again, though the next one will be. */
  later(offer: UpdateOffer): void {
    this.facts.putOff(offer.kind, offer.version);
    this.found = this.found.filter((each) => each.kind !== offer.kind);
    this.why = undefined;
    this.changed();
  }
}
