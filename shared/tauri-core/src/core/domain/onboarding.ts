import type { Platform } from './platform';

/**
 * The first run as the Mac's `OnboardingWindow` runs it: a veil with the wordmark, the name asked for, then
 * three steps in their own window. The words here are the Mac's, said for a computer rather than a Mac.
 */
export type OnboardingStage = 'intro' | 'name' | 'steps';

export const ONBOARDING_STEPS = ['What Memnox does', 'Set up this computer', 'Try it'] as const;
export type OnboardingStep = 0 | 1 | 2;

/** How far the progress bar is filled at a step: a third, two thirds, then whole. */
export function progressOf(step: OnboardingStep): number {
  return (step + 1) / ONBOARDING_STEPS.length;
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
  /** Said over the opening, with the same words it shows. */
  name: 'Welcome to Memnox. I’m the voice over your agents. So, what should I call you?',
  welcome(name: string | undefined): string {
    return `Hi${greeting(name)}, I’m Memnox. I live in the island at the top of your screen and watch over your AI agents, so they can work on their own and stay inside the boundaries you set. Click any line to see it on the island.`;
  },
  /** What Memnox puts on this computer and why each grant is asked, said before any of it happens. */
  setup(platform: Platform): string {
    const asks =
      platform === 'windows'
        ? 'From you I need two things: the microphone to hear you, and Windows Hello so only you approve.'
        : platform === 'linux'
          ? 'From you I need two things: a microphone to hear you, and your password so only you approve.'
          : 'From you I need four permissions: the microphone to hear you, Accessibility to type into your agent’s app, Screen Recording to read the window you ask about, and Touch ID so only you approve.';
    return `Here is what I will do on this computer. I install the Memnox service in your home folder and keep it running and up to date. I connect it to the agents I find, like Claude Code, Codex and Cursor, so what they do passes your rules first. And I install my voice, which runs on this computer. ${asks}`;
  },
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
