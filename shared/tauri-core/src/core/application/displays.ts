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
import { DISPLAY_VIA } from '@memnox/core/wire';
import { isAppLink, launchPlan } from '../domain/session-focus';
import type { DaemonLink } from './ports/daemon-link';
import { requestOnce } from './ports/daemon-link';
import type { Shown, Terminals } from './ports/terminals';
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
 * and Linux do not do by design: nothing here presses keys in another app, raises its window by itself
 * or reads its screen, so nothing is typed, pressed or closed.
 */
export interface Presenter {
  /** The live window on a session, kept up to date while it is open. */
  live(sessionId: string, host: DisplayHost | undefined): Promise<void>;
  /**
   * The sessions on a shelf, turned to this one, then its own tab or editor brought forward through that
   * tool's own controls, and its live window when that could not be done, with why.
   */
  focus(sessionId: string, host: DisplayHost | undefined): Promise<Shown>;
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

/** What the displays reach beyond Memnox's own windows, each optional so a window that only draws needs neither. */
export interface DisplayOptions {
  /** Each tool's own controls, for LAUNCH and APP. */
  readonly terminals?: Terminals;
  /** Stay where I am: words and new agents go only where they land without taking the person's window. */
  readonly stayPut?: () => boolean;
}

/** What the runtime names as the session of a show that belongs to none. */
const NO_SESSION = 'all';
/** The two schemes the runtime's open_link allows. */
const WEB_SCHEMES = ['http', 'https'];

/**
 * Why each display this computer does not do was not done, said to the brain so it never claims it was.
 * On Windows and Linux Memnox presses no key in another app and raises no window by itself, so typing,
 * pressing and closing are left to the person, and each reason says what still happened.
 */
export const CANNOT = {
  [DISPLAY.TYPE]: "this computer does not type into an agent's terminal, so nothing was sent; the person can bring it forward and say it there",
  [DISPLAY.PREFILL]: "this computer does not type into an editor's chat, so nothing was put in it",
  [DISPLAY.CLOSE]: "this computer does not close another app's tabs, so the session is still running in its tab",
  [DISPLAY.INTERRUPT]: 'this computer does not press keys in another app, so the agent was not stopped',
  [DISPLAY.PRESS]: 'this computer does not press keys in another app, so its question was not answered',
  /** A LAUNCH into an editor's agent panel would need its first message typed. */
  panel: "this computer does not type into an editor's agent panel, so nothing was started there",
  /** Without the terminals adapter, as in a window that only draws. */
  launch: 'this computer could not reach a terminal to start it in',
  app: "this computer could not reach the agent's app",
} as const;

/** Said when a LAUNCH names no folder, since a tab or an editor opened anywhere else would start it in the wrong place. */
const NO_FOLDER = 'the repository folder is not known, so there is nowhere to start it';

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
    private readonly options: DisplayOptions = {},
  ) {}

  async handle(event: DaemonEvent): Promise<void> {
    if (event.kind !== DAEMON_EVENT.SHOW) return;
    const host = event.host;
    switch (event.display) {
      case DISPLAY.OPEN:
        if (event.sessionId !== undefined) await this.presenter.live(event.sessionId, host);
        return;
      case DISPLAY.FOCUS: {
        if (event.sessionId === undefined) return;
        const shown = await this.presenter.focus(event.sessionId, host);
        return this.delivered(event, shown.answer, shown.reason);
      }
      case DISPLAY.LAUNCH: {
        const shown = await this.launch(event);
        return this.delivered(event, shown.answer, shown.reason);
      }
      case DISPLAY.APP: {
        const shown = await this.openApp(event);
        return this.delivered(event, shown.answer, shown.reason);
      }
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
        // Nothing here captures the screen, by design, so the brain hears that nothing was seen rather than waiting.
        return this.send({ ...this.request(DAEMON_METHOD.SEEN), subject: event.subject, sight: { app: event.title ?? 'the screen' } });
      case DISPLAY.TYPE:
      case DISPLAY.PREFILL:
      case DISPLAY.CLOSE:
      case DISPLAY.INTERRUPT:
      case DISPLAY.PRESS:
        return this.delivered(event, DELIVERY.FAILED, CANNOT[event.display]);
      default:
        return;
    }
  }

  /**
   * A new tab running the runtime's line in a terminal whose own command line opens one, or the editor the
   * runtime named through the Memnox extension. With Stay where I am on, only a tab opened behind counts.
   */
  private async launch(event: DaemonEvent): Promise<Shown> {
    const terminals = this.options.terminals;
    if (event.via === DISPLAY_VIA.PANEL) return { answer: DELIVERY.FAILED, reason: CANNOT.panel };
    if (terminals === undefined) return { answer: DELIVERY.FAILED, reason: CANNOT.launch };
    const folder = event.host?.cwd;
    if (folder === undefined || folder === '') return { answer: DELIVERY.FAILED, reason: NO_FOLDER };
    const plan = launchPlan(event.host?.appPath ?? event.host?.app, event.via === DISPLAY_VIA.TERMINAL_APP, this.options.stayPut?.() ?? false);
    switch (plan.kind) {
      case 'none':
        return { answer: DELIVERY.FAILED, reason: plan.why };
      case 'editor':
        return terminals.launchInEditor(plan.editor, folder, event.subject);
      case 'terminal':
        return terminals.launchInTerminal(plan.terminal, event.summary, folder, plan.background);
    }
  }

  /**
   * An agent's own app through its registered links, the only links it may open. Words to type into it
   * stay unsaid, since this computer types nothing into another app, and the answer says so.
   */
  private async openApp(event: DaemonEvent): Promise<Shown> {
    const terminals = this.options.terminals;
    const name = event.title ?? event.agent;
    if (terminals === undefined) return { answer: DELIVERY.FAILED, reason: CANNOT.app };
    const links = event.app?.links ?? [];
    if (links.length === 0 || !links.every(isAppLink)) return { answer: DELIVERY.FAILED, reason: `${name} has no link of its own this computer may open, so it was not opened` };
    const shown = await terminals.openAppLinks(links);
    // The summary falls back to the title, so only words the runtime sent count as words to type.
    const words = event.summary !== '' && event.summary !== event.title;
    if (shown.answer !== DELIVERY.TYPED || !words) return shown;
    return { answer: DELIVERY.FAILED, reason: `${name} is open, but this computer types nothing into another app, so the words were not put in` };
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
