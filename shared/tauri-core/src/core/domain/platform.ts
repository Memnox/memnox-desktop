import type { KeyStatus } from './key-status';
import { DONE, needs, WAITING, type StepState } from './step-state';

/** The system the window runs on: the Mac's copy names Touch ID and System Settings, and these name their own. */
export type Platform = 'windows' | 'linux' | 'other';

/** What each system calls the things the Mac's copy names, so one sentence reads right on both. */
export interface PlatformWords {
  /** The key that signs a yes, as a row title: "Windows Hello". */
  readonly keyTitle: string;
  /** The same key as a step: "Approve with Windows Hello". */
  readonly approveTitle: string;
  /** What the key row says it does. */
  readonly keyDetail: string;
  /** The system's own settings app, for "Open {settings}". */
  readonly settingsApp: string;
  /** The keys that start a talk from anywhere, one keycap each. */
  readonly talkKeys: readonly string[];
  /** The same keys in a sentence. */
  readonly talkKeysSaid: string;
}

const TALK_KEYS = ['Ctrl', 'Alt', 'Space'] as const;
const TALK_KEYS_SAID = 'Ctrl Alt Space';

const WORDS: Record<Platform, PlatformWords> = {
  windows: {
    keyTitle: 'Windows Hello',
    approveTitle: 'Approve with Windows Hello',
    keyDetail: 'Your face, finger or PIN approves anything outside a session’s repository. Saying no needs only your voice.',
    settingsApp: 'Settings',
    talkKeys: TALK_KEYS,
    talkKeysSaid: TALK_KEYS_SAID,
  },
  linux: {
    keyTitle: 'Your confirm key',
    approveTitle: 'Approve with your password',
    keyDetail: 'Your password approves anything outside a session’s repository, through a key the keyring guards. Saying no needs only your voice.',
    settingsApp: 'Settings',
    talkKeys: TALK_KEYS,
    talkKeysSaid: TALK_KEYS_SAID,
  },
  other: {
    keyTitle: 'Touch ID',
    approveTitle: 'Approve with Touch ID',
    keyDetail: 'Your finger approves anything outside a session’s repository. Saying no needs only your voice.',
    settingsApp: 'System Settings',
    talkKeys: TALK_KEYS,
    talkKeysSaid: TALK_KEYS_SAID,
  },
};

export function platformWords(platform: Platform): PlatformWords {
  return WORDS[platform];
}

/** Read from the browser's own description of itself, since the webview is the system's. */
export function platformOf(userAgent: string): Platform {
  if (/Windows/i.test(userAgent)) return 'windows';
  if (/Linux|X11/i.test(userAgent) && !/Android/i.test(userAgent)) return 'linux';
  return 'other';
}

/** The key's standing as a setup step, worded as the Mac's `keyState` words it, for this system. */
export function keyStep(status: KeyStatus | undefined, platform: Platform): StepState {
  if (status === undefined) return WAITING;
  switch (status.kind) {
    case 'registered':
      return DONE;
    case 'no-key':
      return needs(
        platform === 'windows'
          ? 'This PC could not make a Windows Hello key. Check Windows Hello is set up in Settings, Accounts, Sign in options, then quit and reopen Memnox'
          : platform === 'linux'
            ? 'This computer could not make a key. Check that a keyring such as GNOME Keyring or KWallet is running, then quit and reopen Memnox'
            : 'This Mac could not make a Touch ID key. Check Touch ID is set up in System Settings, then quit and reopen Memnox',
      );
    case 'another-key':
      return needs('Memnox still trusts a key from an earlier setup. In a terminal, run memnox voice forget-key, then press Check again');
    case 'unreachable':
      return needs('Waiting for the Memnox service');
    case 'too-old':
      return needs('Waiting for a Memnox that knows voice');
    case 'refused':
      return needs(status.why);
  }
}
