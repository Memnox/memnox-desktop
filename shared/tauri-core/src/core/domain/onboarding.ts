import type { PermissionStep } from './permission-steps';
import type { Platform } from './platform';
import type { SettingsPage } from './settings-pages';

/**
 * The first run on a fresh computer, with no account, cut to three short steps as the console's was: a veil with
 * the wordmark, then connect, the grants this system asks for, and the starting rules, each with a safe default
 * already chosen. The end screen offers one next action; the name, the voice, the workspace and the phone are
 * optional there and in Settings, never a step.
 */
export type OnboardingStage = 'intro' | 'steps' | 'done';

export const ONBOARDING_STEPS = ['Connect', 'Permissions', 'Starting rules'] as const;
export type OnboardingStep = 0 | 1 | 2;

/** "Step 2 of 3", over each step's title. */
export function stepCounter(step: OnboardingStep): string {
  return `Step ${step + 1} of ${ONBOARDING_STEPS.length}`;
}

/** How far the progress bar is filled: a third, two thirds, then whole, and whole again on the end screen. */
export function progressOf(step: OnboardingStep, stage: OnboardingStage = 'steps'): number {
  if (stage === 'done') return 1;
  return (step + 1) / ONBOARDING_STEPS.length;
}

/** The title and the line under it on each step. */
export function stepHeading(step: OnboardingStep, keyTitle: string): { readonly title: string; readonly detail: string } {
  switch (step) {
    case 0:
      return { title: 'Connect your agents', detail: `The Memnox service starts by itself and ${keyTitle} becomes the key only you approve with. No account needed.` };
    case 1:
      return { title: 'Permissions', detail: 'Only what this computer asks you for. Everything else installs by itself.' };
    case 2:
      return { title: 'Starting rules', detail: `The recommended rules are chosen for you. Each one holds once you confirm it with ${keyTitle} on the island.` };
  }
}

/**
 * The grants this system actually asks the person for: a switch the system guards, such as the Windows microphone,
 * or anything still left to do. A row the system never asks about is not listed, since there is nothing to press.
 */
export function permissionsAsked(steps: readonly PermissionStep[]): readonly PermissionStep[] {
  return steps.filter((step) => step.state.kind !== 'done' || step.switchName !== undefined);
}

/** The line over the grants: still asking, nothing to grant, every one granted, or how many are left. */
export function permissionsLine(asked: readonly PermissionStep[]): string {
  if (asked.some((step) => step.state.kind === 'waiting')) return 'Asking this computer what it needs.';
  const left = asked.filter((step) => step.state.kind === 'needs').length;
  if (asked.length === 0) return 'Nothing to grant. This computer lets Memnox hear, type and see without asking.';
  if (left === 0) return 'Everything this computer asks for is granted.';
  return left === 1 ? 'One grant left. Memnox carries on without it, and asks again in Settings.' : `${left} grants left. Memnox carries on without them, and asks again in Settings.`;
}

/** The pack the first run starts on, the same safe defaults the runtime ships. */
export const RECOMMENDED_PACK = 'safe-defaults';

/** The packs as the last step lists them: the recommended one chosen, the rest behind See other packs. */
export function startingPacks<Pack extends { readonly id: string }>(packs: readonly Pack[]): { readonly recommended: Pack | undefined; readonly others: readonly Pack[] } {
  const recommended = packs.find((pack) => pack.id === RECOMMENDED_PACK) ?? packs[0];
  return { recommended, others: packs.filter((pack) => pack !== recommended) };
}

/** One optional thing the end screen offers, opening the Settings page that holds it. */
export interface EndLink {
  readonly id: 'name' | 'voice' | 'workspace' | 'phone';
  readonly title: string;
  readonly detail: string;
  readonly page: SettingsPage;
}

/** What the end screen offers after its one next action, the name dropped once it is given. */
export function endLinks(name: string | undefined): readonly EndLink[] {
  const all: readonly EndLink[] = [
    { id: 'name', title: 'Tell Memnox your name', detail: 'So it greets you by name.', page: 'account' },
    { id: 'voice', title: 'Pick a voice', detail: 'Who answers when you talk, and how it sounds.', page: 'voice' },
    { id: 'workspace', title: 'Sign in to your workspace', detail: 'Share rules and approvals with your team.', page: 'account' },
    { id: 'phone', title: 'Pair your phone', detail: 'Answer your agents when you are away.', page: 'phones' },
  ];
  return name === undefined || name.trim() === '' ? all : all.filter((link) => link.id !== 'name');
}

/** One of the five things Memnox does, each a row the first step lists. */
export interface WelcomeRow {
  readonly id: 'glance' | 'answer' | 'rule' | 'tools' | 'catch-up';
  readonly title: string;
  readonly detail: string;
}

export const WELCOME_ROWS: readonly WelcomeRow[] = [
  { id: 'glance', title: 'See every agent at a glance', detail: 'Claude Code, Codex and Cursor in the island, each one a click from what it is changing.' },
  { id: 'answer', title: 'Answer your agents from the island', detail: 'When an agent wants to push to main, it asks you here. One click, and it carries on.' },
  { id: 'rule', title: 'Say a rule out loud', detail: '“Never push to main without asking me.” Memnox writes it down and every agent keeps it.' },
  {
    id: 'tools',
    title: 'Act in your own tools, as you',
    detail: 'Reply on a pull request, send a Slack DM or an email in your own name. You see the draft and send it with your approval.',
  },
  { id: 'catch-up', title: 'Catch up by asking', detail: '“What did my agents do while I was out?” The answer comes back in a sentence.' },
];

/** What the guide calls the key a yes is signed with, where the Mac says Touch ID. */
const KEY_SAID: Record<Platform, string> = { windows: 'Windows Hello', linux: 'your password', other: 'Touch ID' };

/** " Moise" with a name and nothing without one, as the Mac's `greeting` writes it. */
function greeting(name: string | undefined): string {
  const trimmed = name?.trim() ?? '';
  return trimmed === '' ? '' : ` ${trimmed}`;
}

/**
 * What the guide says at each stage, as the Mac's `GuideLines` says it, with the island where the Mac
 * has its notch and each system's own key and grants where the Mac names Touch ID and System Settings.
 */
export const GuideLines = {
  welcome(name: string | undefined): string {
    return `Hi${greeting(name)}, I’m Memnox. I live in the island at the top of your screen and watch over your AI agents, so they can work on their own and stay inside the boundaries you set. No account needed.`;
  },
  /** What Memnox puts on this computer and the one thing it asks for now, said before any of it happens. */
  setup(platform: Platform): string {
    return `Here is what I will do on this computer. I install the Memnox service in your home folder and keep it running and up to date, and I connect it to the agents I find, like Claude Code, Codex and Cursor, so what they do passes your rules first. From you I need one thing now: ${KEY_SAID[platform]} so only you approve.`;
  },
  /** Said over the second step, which lists only what this system asks for. */
  permissions: 'Next, the few things this computer asks you to allow. Everything else I install myself.',
  /** Said over the third step: a pack is only proposed, and each rule waits for the person. */
  boundaries(platform: Platform): string {
    return `Last, your starting rules. The recommended ones are already chosen, and each holds once you confirm it with ${KEY_SAID[platform]} on the island. You can change any of them later.`;
  },
  /** Said on the end screen, over its one next action and what is optional. */
  done: 'That is everything your agents need. Your name, a voice and your phone are optional, and wait in Settings.',
  /** Said when hearing waits on a switch the person has to turn on. */
  microphone(platform: Platform): string {
    return platform === 'windows'
      ? 'Settings is opening. Under Privacy and security, Microphone, switch on Let desktop apps access your microphone, then come back here.'
      : 'I cannot find a microphone on this computer. Plug one in or pick one in your sound settings, then press Check again.';
  },
  /** Said when typing waits on the person, which only Wayland asks. */
  typing: 'Wayland lets me type into other apps only through uinput. Follow the steps on screen, then press Check again.',
  /** Said when seeing waits on the person, as the Mac's seeing line, for what each Linux desktop lacks. */
  seeing(why: 'portal' | 'accessibility'): string {
    return why === 'portal'
      ? 'Your desktop has no screen sharing portal answering, which is how Wayland lets me see a window. Follow the steps on screen, then press Check again.'
      : 'The accessibility bus is off, so I cannot read the outline of a window. Follow the steps on screen, then press Check again.';
  },
  ready(name: string | undefined, talkKeys: string): string {
    return `You’re all set${greeting(name)}. Press ${talkKeys} and say what you need. When an agent needs you, I will ask right here in the island.`;
  },
} as const;

/** What the guide says as the island plays a part, written to be heard rather than read, as the Mac's `Highlight.spoken`. */
export function rowSpoken(row: WelcomeRow['id'], platform: Platform): string {
  switch (row) {
    case 'glance':
      return 'Every agent you run, like Claude Code, Codex or Cursor, shows up here in the island. Click one to see what it is changing.';
    case 'answer':
      return 'When an agent wants to do something that matters, like pushing to main, it asks you here. One click, and it carries on.';
    case 'rule':
      return 'Say a rule out loud, like never push to main without asking me, and every agent keeps it from then on.';
    case 'tools':
      return `I can act in your own tools as you, like replying on a pull request or sending a message. You see the draft first, and send it with ${KEY_SAID[platform]}.`;
    case 'catch-up':
      return 'And when you come back, just ask what your agents did. I will tell you in a sentence.';
  }
}

/**
 * Which lines the guide has said, so each step is introduced once in a first run and each part only the
 * first time the island plays it, as the Mac's `firstVisit` and `narrated`.
 */
export class GuideMemory {
  private readonly said = new Set<string>();

  /** True the first time this line's key is asked about, false every time after. */
  first(key: string): boolean {
    if (this.said.has(key)) return false;
    this.said.add(key);
    return true;
  }
}

/** The title of the last step, with the name when there is one. */
export function setTitle(name: string | undefined): string {
  return name === undefined ? 'You’re set.' : `You’re set, ${name}.`;
}
