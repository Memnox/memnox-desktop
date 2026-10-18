import type { Platform } from './platform';
import { DONE, needs, WAITING, type StepState } from './step-state';

/**
 * What this computer told Rust about the three things the Mac asks for: hearing, typing and seeing. The
 * questions are the Mac's, the answers are each system's: Windows guards the microphone behind a privacy
 * switch and lets an app type and read the screen; Linux has no microphone switch, lets X11 apps type, and
 * on Wayland types only through uinput.
 */
export interface PermissionFacts {
  readonly platform: Platform;
  readonly session: 'desktop' | 'x11' | 'wayland';
  readonly microphone: 'allowed' | 'denied' | 'none' | 'unknown';
  readonly typing: boolean;
}

export type PermissionId = 'hear' | 'type' | 'see';

/** The system page a step's Open button goes to, as `open_privacy` names it in Rust. */
export type PrivacyPane = 'microphone' | 'sound' | 'typing' | 'screen';

/** One row of the Permissions page and of the first run's Permissions card. */
export interface PermissionStep {
  readonly id: PermissionId;
  readonly title: string;
  /** The line under the title on the Permissions page. */
  readonly detail: string;
  /** The shorter line the first run's card uses, naming what the system calls it. */
  readonly onboardingDetail: string;
  readonly state: StepState;
  /** What to do, one step a line, shown under a row that needs the person, as the Mac's `PermissionGuide`. */
  readonly guide: readonly string[];
  /** The system page that holds the switch, when there is one. */
  readonly pane: PrivacyPane | undefined;
  /** The switch the picture in the guide shows, by the name the system gives it. */
  readonly switchName: string | undefined;
}

const HEAR_DETAIL = 'The microphone, heard on this computer only.';
const TYPE_DETAIL = 'Type what you confirm into your agents, and read back that it landed.';
const SEE_DETAIL = 'Read the window you ask about, and check that what it sent landed.';

/** The Windows privacy switch, named as Settings names it. */
const WINDOWS_MIC_GUIDE = [
  'In Settings, open Privacy and security, then Microphone.',
  'Switch on Microphone access, and Let desktop apps access your microphone.',
  'Come back here. This row turns on by itself once the switch is on.',
];

const LINUX_NO_MIC_GUIDE = [
  'Plug in a microphone, or a headset with one.',
  'In Sound settings, choose it as the input device.',
  'Press Check again.',
];

/** uinput is root only on most distributions, so the input group and a rule for it let Memnox type on Wayland. */
const WAYLAND_TYPING_GUIDE = [
  'Open a terminal and run sudo usermod -aG input $USER, which lets Memnox type through uinput.',
  'If your distribution keeps uinput for root, add KERNEL=="uinput", GROUP="input", MODE="0660" to /etc/udev/rules.d/60-memnox.rules.',
  'Sign out and back in, then press Check again.',
];

/** Hearing, typing and seeing on this computer, in the order the Mac lists them. */
export function permissionSteps(facts: PermissionFacts): readonly PermissionStep[] {
  return [hear(facts), type(facts), see(facts)];
}

function hear(facts: PermissionFacts): PermissionStep {
  const base = { id: 'hear' as const, title: 'Hear you', detail: HEAR_DETAIL };
  if (facts.platform === 'windows') {
    const denied = facts.microphone === 'denied';
    return {
      ...base,
      onboardingDetail: 'Microphone access for desktop apps.',
      state: denied ? needs('Turn on Let desktop apps access your microphone in Settings, Privacy and security, Microphone') : DONE,
      guide: denied ? WINDOWS_MIC_GUIDE : [],
      pane: 'microphone',
      switchName: 'Let desktop apps access your microphone',
    };
  }
  const none = facts.microphone === 'none';
  return {
    ...base,
    onboardingDetail: 'A microphone to hear you with. Linux asks nothing more.',
    state: none ? needs('No microphone found on this computer') : DONE,
    guide: none ? LINUX_NO_MIC_GUIDE : [],
    pane: 'sound',
    switchName: undefined,
  };
}

function type(facts: PermissionFacts): PermissionStep {
  const base = { id: 'type' as const, title: 'Type for you', detail: TYPE_DETAIL };
  if (facts.platform === 'windows') {
    return {
      ...base,
      onboardingDetail: 'Windows lets Memnox type into any app not running as administrator.',
      state: DONE,
      guide: [],
      pane: undefined,
      switchName: undefined,
    };
  }
  if (facts.session === 'wayland' && !facts.typing) {
    return {
      ...base,
      onboardingDetail: 'Wayland lets an app type only through uinput, so a follow up lands in the agent’s own app.',
      state: needs('Wayland lets Memnox type only through uinput, which it cannot reach yet'),
      guide: WAYLAND_TYPING_GUIDE,
      pane: undefined,
      switchName: undefined,
    };
  }
  return {
    ...base,
    onboardingDetail: facts.session === 'wayland' ? 'Typing through uinput, so a follow up lands in the agent’s own app.' : 'X11 lets Memnox type, so a follow up lands in the agent’s own app.',
    state: DONE,
    guide: [],
    pane: undefined,
    switchName: undefined,
  };
}

function see(facts: PermissionFacts): PermissionStep {
  const base = { id: 'see' as const, title: 'See your screen', detail: SEE_DETAIL, guide: [], pane: undefined, switchName: undefined };
  if (facts.platform === 'linux' && facts.session === 'wayland') {
    return { ...base, onboardingDetail: 'Your desktop asks the first time, through its own screenshot prompt.', state: DONE };
  }
  return {
    ...base,
    onboardingDetail: facts.platform === 'windows' ? 'Windows lets Memnox read the window you ask about, with no switch to turn on.' : 'Read the window you ask about and check that words landed.',
    state: DONE,
  };
}

/** The facts before Rust has answered, which show every row as still to check. */
export const UNKNOWN_FACTS: PermissionFacts = { platform: 'other', session: 'desktop', microphone: 'unknown', typing: false };

/** Every row still waiting, for the moment before the facts arrive. */
export function waitingSteps(): readonly PermissionStep[] {
  return permissionSteps(UNKNOWN_FACTS).map((step) => ({ ...step, state: WAITING }));
}
