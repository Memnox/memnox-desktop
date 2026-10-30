import type { Platform } from './platform';

/**
 * The first run on a fresh computer, with no account: a veil with the wordmark, the name asked for, then
 * three steps that connect the agents, bring in what they already have, and choose the boundaries. The
 * voice, the permissions it needs and the phone come after, each optional.
 */
export type OnboardingStage = 'intro' | 'name' | 'steps' | 'optional';

export const ONBOARDING_STEPS = ['Connect your agents', 'Set up your workspace', 'Choose your boundaries'] as const;
export type OnboardingStep = 0 | 1 | 2;

/** How far the progress bar is filled: a third, two thirds, then whole, and whole again for what is optional. */
export function progressOf(step: OnboardingStep, stage: OnboardingStage = 'steps'): number {
  if (stage === 'optional') return 1;
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
    return `Hi${greeting(name)}, I’m Memnox. I live in the island at the top of your screen and watch over your AI agents, so they can work on their own and stay inside the boundaries you set. No account needed.`;
  },
  /** What Memnox puts on this computer and the one thing it asks for now, said before any of it happens. */
  setup(platform: Platform): string {
    return `Here is what I will do on this computer. I install the Memnox service in your home folder and keep it running and up to date, and I connect it to the agents I find, like Claude Code, Codex and Cursor, so what they do passes your rules first. From you I need one thing now: ${KEY_SAID[platform]} so only you approve.`;
  },
  /** Said over the second step, before anything is brought in. */
  workspace: 'Your agents already have servers and skills of their own. Bring them in with one tap, so each is set up once and given to the agents you choose.',
  /** Said over the third step: a pack is only proposed, and each rule waits for the person. */
  boundaries(platform: Platform): string {
    return `Last, choose your boundaries. Pick a pack of rules to start from, and confirm each rule with ${KEY_SAID[platform]} on the island. You can change any of them later.`;
  },
  /** Said once the three steps are done, over what is left and optional. */
  optional: 'That is everything your agents need. The rest is optional: the microphone so you can talk to me, a voice to answer, and your phone for when you are away.',
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
