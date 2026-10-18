import {
  DAEMON_EVENT,
  DAEMON_METHOD,
  DELIVERY,
  DISPLAY,
  type CardExcerpt,
  type CardFile,
  type DaemonEvent,
  type DaemonRequest,
  type Delivery,
  type DisplayHost,
  type TraceCard,
  type WalkPage,
} from '@memnox/core/wire';
import type { DaemonLink } from './ports/daemon-link';
import { requestOnce } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** A summary card put on screen while the voice reads it, ported from the Mac's `SummaryCard`. */
export interface SummaryCard {
  readonly title: string;
  /** Read, not heard, so the markdown stays for the card to lay out. */
  readonly text: string;
  readonly files: readonly CardFile[];
  readonly excerpt?: CardExcerpt;
  /** The session it is about; undefined for a card about none, which offers no window. */
  readonly sessionId?: string;
  readonly host?: DisplayHost;
  readonly agent?: string;
}

/** A card that turns a page per changed file while the voice walks through the change. */
export interface WalkCard {
  readonly title: string;
  readonly pages: readonly WalkPage[];
  readonly sessionId?: string;
  readonly host?: DisplayHost;
  readonly agent?: string;
}

/**
 * What puts a session in front of the person on this computer, the Mac's `Presenter` less what Windows
 * and Linux cannot do yet: there is no reading of terminal tabs here, so nothing is typed, pressed or closed.
 */
export interface Presenter {
  /** The live window on a session, kept up to date while it is open. */
  live(sessionId: string, host: DisplayHost | undefined): Promise<void>;
  /** The sessions on a shelf, turned to this one, then its live window. */
  turnTo(sessionId: string): Promise<void>;
  card(card: SummaryCard): Promise<void>;
  /** Every session as its own card, together; the window reads the sessions itself. */
  board(title: string): Promise<void>;
  walk(walk: WalkCard): Promise<void>;
  trace(trace: TraceCard, title: string): Promise<void>;
  /** Every card and window off the screen; no session is touched. */
  dismissAll(): Promise<void>;
  /** A folder opened in the file manager, and whether it opened. */
  openFolder(path: string): Promise<boolean>;
  /** A web page opened in the person's own browser, and whether it opened. */
  openLink(url: string): Promise<boolean>;
}

/** What the runtime names as the session of a show that belongs to none. */
const NO_SESSION = 'all';
/** The two schemes the runtime's open_link allows. */
const WEB_SCHEMES = ['http', 'https'];

/** Why each display this computer cannot do yet was not done, said to the brain so it never claims it was. */
const CANNOT: Partial<Record<string, string>> = {
  [DISPLAY.TYPE]: 'this computer cannot type into a terminal yet',
  [DISPLAY.PREFILL]: 'this computer cannot type into an editor chat yet',
  [DISPLAY.LAUNCH]: 'this computer cannot start an agent in a terminal yet',
  [DISPLAY.APP]: "this computer cannot open an agent's app yet",
  [DISPLAY.CLOSE]: "this computer cannot close a session's tab yet",
  [DISPLAY.INTERRUPT]: "this computer cannot press keys in a session's terminal yet",
  [DISPLAY.PRESS]: "this computer cannot press keys in a session's terminal yet",
};

/** The one web address a LINK carries, only http or https with a host and no credentials, so a link never starts an app. */
export function webLink(event: DaemonEvent): string | undefined {
  const text = event.app?.links[0];
  if (event.display !== DISPLAY.LINK || text === undefined) return undefined;
  // Read by hand, since the core has no URL of its own: a scheme, then a host with no name or password in it.
  const match = /^([a-z][a-z0-9+.-]*):\/\/([^/?#\s]*)\S*$/i.exec(text.trim());
  const scheme = match?.[1]?.toLowerCase();
  const authority = match?.[2] ?? '';
  if (scheme === undefined || !WEB_SCHEMES.includes(scheme) || authority === '' || authority.includes('@')) return undefined;
  return text.trim();
}

/** The session a card is about, or undefined for one about none, such as a list of pull requests. */
export function cardSession(event: DaemonEvent): string | undefined {
  return event.sessionId === NO_SESSION ? undefined : event.sessionId;
}

/**
 * The daemon's SHOW events, ported from the Mac's `Conversation.show`: a window or a card put up while the
 * answer is still being said. What this computer cannot do is reported to the daemon as not done, with
 * why, so the voice says that rather than what it hoped. The draft and sign in displays belong to the
 * work cards, which draw them in the island, so they are left to that screen.
 */
export class Displays {
  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
    private readonly presenter: Presenter,
  ) {}

  async handle(event: DaemonEvent): Promise<void> {
    if (event.kind !== DAEMON_EVENT.SHOW) return;
    const host = event.host;
    switch (event.display) {
      case DISPLAY.OPEN:
        if (event.sessionId !== undefined) await this.presenter.live(event.sessionId, host);
        return;
      case DISPLAY.FOCUS:
        if (event.sessionId === undefined) return;
        await this.presenter.turnTo(event.sessionId);
        // Its live window is up, but its own terminal tab did not come forward, which the brain must not claim.
        return this.delivered(event, DELIVERY.FAILED, "this computer cannot bring a session's own tab forward yet, so its live window is open instead");
      case DISPLAY.CARD:
        return this.presenter.card({
          title: event.title ?? 'Session',
          text: event.summary,
          files: event.files ?? [],
          excerpt: event.excerpt,
          sessionId: cardSession(event),
          host,
          agent: event.agent,
        });
      case DISPLAY.WALK:
        return this.presenter.walk({ title: event.title ?? 'Walk through', pages: event.pages ?? [], sessionId: cardSession(event), host, agent: event.agent });
      case DISPLAY.TRACE:
        if (event.trace !== undefined) await this.presenter.trace(event.trace, event.title ?? 'Trace');
        return;
      case DISPLAY.SESSIONS:
        return this.presenter.board(event.title ?? 'Your sessions');
      case DISPLAY.DISMISS:
        return this.presenter.dismissAll();
      case DISPLAY.FOLDER:
        if (host?.cwd === undefined || !(await this.presenter.openFolder(host.cwd))) return this.delivered(event, DELIVERY.FAILED, 'could not open that folder');
        return;
      case DISPLAY.LINK: {
        const url = webLink(event);
        const opened = url !== undefined && (await this.presenter.openLink(url));
        return this.delivered(event, opened ? DELIVERY.TYPED : DELIVERY.FAILED, opened ? undefined : 'not a web page this computer could open');
      }
      case DISPLAY.LOOK:
        // Nothing here captures the screen yet, so the brain hears that nothing was seen rather than waiting.
        return this.send({ ...this.request(DAEMON_METHOD.SEEN), subject: event.subject, sight: { app: event.title ?? 'the screen' } });
      default: {
        const why = event.display === undefined ? undefined : CANNOT[event.display];
        if (why !== undefined) return this.delivered(event, DELIVERY.FAILED, why);
      }
    }
  }

  private delivered(event: DaemonEvent, outcome: Delivery, reason?: string): Promise<void> {
    return this.send({ ...this.request(DAEMON_METHOD.DELIVERED), subject: event.subject, answer: outcome, ...(reason === undefined ? {} : { reason }) });
  }

  private async send(request: DaemonRequest): Promise<void> {
    await requestOnce(this.link, request).catch(() => undefined);
  }

  private request(method: DaemonRequest['method']): DaemonRequest {
    return { id: this.ids.next(), method };
  }
}
