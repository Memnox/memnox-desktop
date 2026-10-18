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

/** What the guide says at each stage, as the Mac's `OnboardingGuide` says it. */
export const GuideLines = {
  name: 'Welcome to Memnox. I’m the voice over your agents. So, what should I call you?',
  welcome(name: string | undefined): string {
    const hello = name === undefined ? 'Hi' : `Hi ${name}`;
    return `${hello}, I’m Memnox. I live at the top of your screen and watch over your AI agents, so they can work on their own and stay inside the boundaries you set.`;
  },
  setup: 'Now let’s set up this computer. Memnox installs itself and its voice, and asks only for what your system needs from you.',
  ready(name: string | undefined, talkKeys: string): string {
    return `You’re set${name === undefined ? '' : `, ${name}`}. Press ${talkKeys} from anywhere and ask me about your agents.`;
  },
} as const;

/** The title of the last step, with the name when there is one. */
export function setTitle(name: string | undefined): string {
  return name === undefined ? 'You’re set.' : `You’re set, ${name}.`;
}
