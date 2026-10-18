import { invoke } from '@tauri-apps/api/core';
import { emit } from '@tauri-apps/api/event';
import { ASK_INTENT, DAEMON_EVENT, DISPLAY, type DaemonEvent, type ToolSignIn } from '@memnox/core/wire';
import type { HeldCalls, HeldOutcome, Talking, Timer } from '../../core';
import { Chiming } from '../../core/application/chiming';
import { Diary } from '../../core/application/diary';
import { IslandNotices, type SignedInPill } from '../../core/application/island-notices';
import type { Chimes } from '../../core/application/ports/chimes';
import type { PressEnd } from '../../core/domain/chimes';
import { toolkitName } from '../../core/domain/tool-brand';
import { answerMenuOpened, forwardCards, onCardSession, onMenuAction, showScan } from '../adapters/tauri-windows';

/** How the talk key reads on Windows and Linux. */
const TALK_KEYS = ['Ctrl', 'Alt', 'Space'];
/** A sign in that finished this long after it was asked carries on what was asked; older, it is only shown. */
const RESUME_WITHIN_MS = 60_000;
/** What the diary's heading says this computer is. */
const MACHINE = navigator.userAgent.includes('Windows') ? 'Windows' : 'Linux';

/** What the island's composition root hands in; everything the voice owns is optional. */
export interface ExtrasParts {
  readonly calls: HeldCalls;
  readonly talking: Talking;
  readonly timer: Timer;
  /** The voice's chimes, already honouring the person's choice; none plays without them. */
  readonly chimes?: Chimes;
  /** The voice's mute, for the tray's row and its words. */
  readonly mute?: () => { on: boolean; toggle: () => void };
  /** Starts listening for a spoken rule. */
  readonly sayRule?: () => void;
  /** Whether the voice wakes when its name is said, for the tray's badge. */
  readonly wakesByName?: () => boolean;
}

/** What the island draws and calls from here. */
export interface IslandExtras {
  readonly notices: IslandNotices;
  readonly diary: Diary;
  readonly chiming: Chiming;
  readonly onSignIn: (tool: ToolSignIn) => void;
  readonly onNotMe: (pill: SignedInPill) => void;
  /** Every answer given by hand on a held call, for its chime and the diary. */
  readonly answered: (answer: string, outcome: HeldOutcome) => void;
  /** Every answer given on a rule or work card. */
  readonly proposalAnswered: (outcome: HeldOutcome, sent: boolean) => void;
}

/**
 * The tray, the pills under the island and the chimes, wired to the island's own parts: the live feed
 * goes to the pills, the chimes and the diary, and every tray row is carried out here or handed to the
 * command that owns it, so the panel never does anything itself.
 */
export function islandExtras(parts: ExtrasParts): IslandExtras {
  const notices = new IslandNotices(parts.timer);
  const diary = new Diary();
  const chiming = new Chiming(parts.chimes ?? { play: () => undefined }, () => notices.state.phoneVoice !== undefined);

  parts.calls.observeEvents((event) => {
    notices.handle(event);
    chiming.heard(event);
    diary.note(describe(event));
    carryOn(event);
    // The scan of every agent here takes the whole screen; `Displays` leaves this one display to it.
    if (event.kind === DAEMON_EVENT.SHOW && event.display === DISPLAY.AGENTS && event.agents !== undefined) void showScan(event.agents, event.title ?? 'Your agents').catch(() => undefined);
  });
  forwardCards();
  // A card's Watch live and Open both bring up the live window, since no session window is focused here yet.
  onCardSession((ask) => void invoke('open_live_session', { sessionId: ask.sessionId }).catch(() => undefined));

  /** A sign in that finished goes on with what the person asked before it, as if they asked again. */
  function carryOn(event: DaemonEvent) {
    const resume = event.signedIn?.resume;
    if (event.kind !== DAEMON_EVENT.NOTICE || event.notice !== 'signed-in' || resume === undefined || event.signedIn?.account === undefined) return;
    if (Date.now() - Date.parse(event.at) > RESUME_WITHIN_MS) return;
    // Marked as asked again, so nothing the brain proposes from it counts as words the person just said.
    void parts.talking.heard(resume, true, { intent: ASK_INTENT.RESUME });
  }

  onMenuAction((action) => {
    diary.note(`tray: ${action}`);
    switch (action) {
      case 'talk':
        void emit('talk', null);
        return;
      case 'rule':
        parts.sayRule?.();
        return;
      case 'copy':
        void invoke('clipboard_set', { text: diary.text(MACHINE) }).catch(() => undefined);
        return;
      case 'mute':
        parts.mute?.().toggle();
        return;
      case 'settings':
        void invoke('open_settings', { page: null }).catch(() => undefined);
        return;
      case 'tools':
        void invoke('open_settings', { page: 'tools' }).catch(() => undefined);
        return;
      case 'quit':
        return;
    }
  });
  answerMenuOpened(() => ({ muted: parts.mute?.().on ?? false, wakesByName: parts.wakesByName?.() ?? false, talkKeys: TALK_KEYS }));

  return {
    notices,
    diary,
    chiming,
    onSignIn: (tool) => {
      // Only a web page is opened, so a link in an event never starts an app.
      if (!tool.url.startsWith('https://')) {
        diary.note(`not opening the ${tool.toolkit} sign in, since its link is not https`);
        return;
      }
      notices.signingIn(tool.toolkit);
      diary.note(`opened the ${tool.toolkit} sign in`);
      void invoke('open_link', { url: tool.url }).catch(() => undefined);
    },
    onNotMe: (pill) => {
      notices.dismissSignedIn();
      diary.note(`not me on ${pill.toolkit}`);
      // Said as the person would say it, so the brain opens a fresh sign in with their own account.
      void parts.talking.heard(`Sign me in to ${toolkitName(pill.toolkit)} again, with my own account`, true);
    },
    answered: (answer, outcome) => {
      chiming.answered(answer, outcome.kind as PressEnd);
      diary.note(`answered ${answer}: ${outcome.kind}`);
    },
    proposalAnswered: (outcome, sent) => {
      chiming.proposalAnswered(sent, outcome.kind as PressEnd);
      diary.note(`card ${sent ? 'sent' : 'declined'}: ${outcome.kind}`);
    },
  };
}

/** One diary line for an event: its kind, what it was and its id, never its words or arguments. */
function describe(event: DaemonEvent): string {
  const what = event.notice ?? event.display;
  return `${event.kind}${what === undefined ? '' : ` ${what}`} ${event.subject} from ${event.agent}`;
}
