import type { CapabilityLevel, CapabilityLevels } from './agent-wire';
import { LEVEL_WORDS, levelRows, seamRows } from './capability-level-lines';
import type { Platform } from './platform';
import type { SettingsPage } from './settings-pages';

/**
 * The first run on a fresh computer, with no account, as the Mac's: a veil with the wordmark, then the two steps that
 * cannot wait, this computer connected and the rules its agents start under, each with a safe default already chosen.
 * The end screen offers one prompt to try and one button that opens Memnox, then says what Memnox can and cannot do.
 */
export type OnboardingStage = 'intro' | 'steps' | 'done';

/**
 * The two steps by their contract ids. The other questions of the contract's `onboarding` list in
 * `shared/ux/contract.json`, who Memnox is for, which agents and where it asks, are answered from Home once Memnox opens.
 */
export const ONBOARDING_IDS = ['connect', 'rules'] as const;
export type OnboardingId = (typeof ONBOARDING_IDS)[number];

/** Each step's question, heading its page, as the contract words it. */
export const ONBOARDING_TITLE: Readonly<Record<OnboardingId, string>> = {
  connect: 'Connect this machine',
  rules: 'Your starting rules',
};

/** The steps by name under the progress bar, as the Mac's stepper names them with "Mac" said as "computer". */
export const ONBOARDING_STEPS = ['This computer', 'Starting rules'] as const;
export type OnboardingStep = 0 | 1;

/** What the end offers to paste into an agent, so the first ask arrives in minutes; the contract's `tryPrompt`. */
export const TRY_PROMPT = 'Make a folder called memnox-try, then delete it with rm -rf memnox-try.';
export const TRY_TITLE = 'Try it with your agent';
export const TRY_DETAIL = 'Paste this into Claude Code, Codex or Cursor. Memnox asks you before the delete runs.';

/** Every step by its number, for a preview's ?step= and for moving on. */
export const STEP_NUMBERS: readonly OnboardingStep[] = [0, 1];

/** The step after this one, or undefined after the last. */
export function nextStep(step: OnboardingStep): OnboardingStep | undefined {
  return STEP_NUMBERS.find((each) => each === step + 1);
}

/** The step before this one, or undefined before the first. */
export function previousStep(step: OnboardingStep): OnboardingStep | undefined {
  return STEP_NUMBERS.find((each) => each === step - 1);
}

/** "Step 1 of 2", over each step's title. */
export function stepCounter(step: OnboardingStep): string {
  return `Step ${step + 1} of ${ONBOARDING_STEPS.length}`;
}

/** How far the progress bar is filled: half, then whole, and whole again on the end screen. */
export function progressOf(step: OnboardingStep, stage: OnboardingStage = 'steps'): number {
  if (stage === 'done') return 1;
  return (step + 1) / ONBOARDING_STEPS.length;
}

/** The title and the line under it on each step. */
export function stepHeading(step: OnboardingStep, keyTitle: string): { readonly title: string; readonly detail: string } {
  const id = ONBOARDING_IDS[step];
  switch (id) {
    case 'connect':
      return { title: ONBOARDING_TITLE.connect, detail: `The Memnox service starts by itself and ${keyTitle} becomes the key only you approve with. No account needed.` };
    case 'rules':
      return { title: ONBOARDING_TITLE.rules, detail: `The recommended rules are chosen for you. Each one holds once you confirm it with ${keyTitle} on the island.` };
  }
}

/** The pack the first run starts on, the same safe defaults the runtime ships. */
export const RECOMMENDED_PACK = 'safe-defaults';

/** The packs as the last step lists them: the recommended one chosen, the rest behind See other packs. */
export function startingPacks<Pack extends { readonly id: string }>(packs: readonly Pack[]): { readonly recommended: Pack | undefined; readonly others: readonly Pack[] } {
  const recommended = packs.find((pack) => pack.id === RECOMMENDED_PACK) ?? packs[0];
  return { recommended, others: packs.filter((pack) => pack !== recommended) };
}

/** Where the rest of setup went, said under the button that opens Memnox, so nobody looks for it here. */
export const END_LATER = 'Pairing your phone waits on Home under Do this next, and Memnox Cloud is in Settings under Account.';

/** One optional thing the end screen offers, opening the Settings page that holds it. */
export interface EndLink {
  readonly id: 'name' | 'voice';
  readonly title: string;
  readonly detail: string;
  readonly page: SettingsPage;
}

/** What the end screen offers after its one next action, the name dropped once it is given. */
export function endLinks(name: string | undefined): readonly EndLink[] {
  const all: readonly EndLink[] = [
    { id: 'name', title: 'Tell Memnox your name', detail: 'So it greets you by name.', page: 'account' },
    { id: 'voice', title: 'Pick a voice', detail: 'Who answers when you talk, and how it sounds.', page: 'voice' },
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
  /** Said once before the first step, so a new person knows how short this is. */
  twoSteps: 'Setup takes two short steps, and I will talk you through both.',
  /** Said over the last step: a pack is only proposed, and each rule waits for the person. */
  boundaries(platform: Platform): string {
    return `Last, your starting rules. The recommended ones are already chosen, and each holds once you confirm it with ${KEY_SAID[platform]} on the island. You can change any of them later.`;
  },
  /** Said on the end screen, over its one next action and what is optional. */
  done: 'That is setup done. Paste the prompt on screen into your agent, and I will ask you before the delete runs. Below it is what I can and cannot do for your agents, in plain words. You can pair your phone or sign in to Memnox Cloud later, from Home and Settings, once Memnox opens.',
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

/** One line of the closing card: a level in plain words and the things an agent does that sit at it. */
export interface CoverageLine {
  readonly level: CapabilityLevel;
  readonly plain: string;
  readonly things: readonly string[];
  /** "Memnox stops this: Commands, Files and Git." */
  readonly sentence: string;
}

/** The levels strongest first, so the card opens on what is held. */
const STRONGEST_FIRST: readonly CapabilityLevel[] = ['enforced', 'mediated', 'advisory', 'observed', 'none'];

/** "Commands, Files and Git", the way a sentence lists things. */
export function joinedThings(things: readonly string[]): string {
  if (things.length <= 1) return things[0] ?? '';
  return `${things.slice(0, -1).join(', ')} and ${things[things.length - 1]}`;
}

/**
 * What Memnox can and cannot do, said at the end of the first run in the five plain levels, as the Mac's
 * `FirstRunCoverage`. Every level is one the service or the cloud stated; nothing here works one out.
 */
export const FirstRunCoverage = {
  title: 'What Memnox can and cannot do',
  lead: 'For each agent found here, from what Memnox has seen and proved so far.',
  cannot: 'Memnox cannot see or stop anything an agent does outside the connections above, and it never acts on its own.',
  noAgents: 'No agent is connected yet, so there is nothing for Memnox to stop or see. Each one you connect shows here and under AI agents.',
  /** The press that opens and closes every agent's levels, since the whole list buries the one thing to do next. */
  showDetails: 'Show what each covers',
  hideDetails: 'Hide the details',
  /** The agent's capabilities and seams grouped by level, strongest first, a level with nothing at it left out. */
  lines(levels: CapabilityLevels): CoverageLine[] {
    const rows = [...levelRows(levels), ...seamRows(levels)];
    return STRONGEST_FIRST.flatMap((level) => {
      const things = rows.filter((row) => row.level === level).map((row) => row.title);
      return things.length === 0 ? [] : [{ level, plain: LEVEL_WORDS[level], things, sentence: `${LEVEL_WORDS[level]}: ${joinedThings(things)}.` }];
    });
  },
} as const;
