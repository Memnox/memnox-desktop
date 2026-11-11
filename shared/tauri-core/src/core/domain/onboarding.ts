import type { CapabilityLevel, CapabilityLevels } from './agent-wire';
import { LEVEL_WORDS, levelRows, seamRows } from './capability-level-lines';
import type { Platform } from './platform';
import type { SettingsPage } from './settings-pages';

/**
 * The first run on a fresh computer, with no account, as the Mac's: a veil with the wordmark, then connect, the grants
 * this system asks for, two questions asked one at a time (the agent's job and where it runs), and the starting rules,
 * each with a safe default already chosen and every question skippable. The end screen says what Memnox can and cannot
 * do in plain words, then offers one next action; Memnox Cloud and the phone are optional there, never a step.
 */
export type OnboardingStage = 'intro' | 'steps' | 'done';

/** The five steps by their contract ids, the same on the console, the Mac, Windows and Linux (`shared/ux/contract.json`). */
export const ONBOARDING_IDS = ['who', 'agents', 'connect', 'ask-where', 'rules'] as const;
export type OnboardingId = (typeof ONBOARDING_IDS)[number];

/** Each step's question, heading its page, as the contract words it. */
export const ONBOARDING_TITLE: Readonly<Record<OnboardingId, string>> = {
  who: 'Who is Memnox for?',
  agents: 'Which agents do you run?',
  connect: 'Connect this machine',
  'ask-where': 'Where should Memnox ask you?',
  rules: 'Your starting rules',
};

/** The steps by name under the progress bar, as the Mac's stepper names them with "Mac" said as "computer". */
export const ONBOARDING_STEPS = ['Who it is for', 'Your agents', 'This computer', 'Where you are asked', 'Starting rules'] as const;
export type OnboardingStep = 0 | 1 | 2 | 3 | 4;

/** What the end offers to paste into an agent, so the first ask arrives in minutes; the contract's `tryPrompt`. */
export const TRY_PROMPT = 'Make a folder called memnox-try, then delete it with rm -rf memnox-try.';
export const TRY_TITLE = 'Try it with your agent';
export const TRY_DETAIL = 'Paste this into Claude Code, Codex or Cursor. Memnox asks you before the delete runs.';

/** Who Memnox is for, which only picks where Where should Memnox ask you suggests first. */
export type Audience = 'me' | 'away' | 'team';

export const AUDIENCES: readonly { readonly id: Audience; readonly title: string; readonly detail: string; readonly suggested: AskRoute }[] = [
  { id: 'me', title: 'Just me', detail: 'My agents on this computer, answered here.', suggested: 'here' },
  { id: 'away', title: "Just me, with agents working while I'm away", detail: 'Agents that keep going when I step out, answered from my phone.', suggested: 'phone' },
  { id: 'team', title: 'A team', detail: 'Agents across people and machines, under the same rules.', suggested: 'cloud' },
];

/** The places Memnox asks a person, each one more way in beside this computer's key, which is always on. */
export type AskRoute = 'here' | 'phone' | 'cloud';

export function askRoutes(keyTitle: string): readonly { readonly id: AskRoute; readonly title: string; readonly detail: string }[] {
  return [
    { id: 'here', title: `${keyTitle} on this computer`, detail: 'Always on. The island asks, and your key signs the yes.' },
    { id: 'phone', title: 'Your phone', detail: 'Pair it with a code here, and answer wherever you are.' },
    { id: 'cloud', title: 'Memnox Cloud, in the browser or chat', detail: 'Sign in, and a question reaches you in the browser or chat your workspace uses.' },
  ];
}

/** The routes in the order the step lists them, the one who it is for suggests first. */
export function askOrder(audience: Audience | undefined): readonly AskRoute[] {
  const first = AUDIENCES.find((each) => each.id === audience)?.suggested ?? 'here';
  return [first, ...(['here', 'phone', 'cloud'] as const).filter((route) => route !== first)];
}

/** Every step by its number, for a preview's ?step= and for moving on. */
export const STEP_NUMBERS: readonly OnboardingStep[] = [0, 1, 2, 3, 4];

/** The step after this one, or undefined after the last. */
export function nextStep(step: OnboardingStep): OnboardingStep | undefined {
  return STEP_NUMBERS.find((each) => each === step + 1);
}

/** The step before this one, or undefined before the first. */
export function previousStep(step: OnboardingStep): OnboardingStep | undefined {
  return STEP_NUMBERS.find((each) => each === step - 1);
}

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
  const id = ONBOARDING_IDS[step];
  switch (id) {
    case 'who':
      return { title: ONBOARDING_TITLE.who, detail: 'It only picks what is suggested next. You can change it later.' };
    case 'agents':
      return { title: ONBOARDING_TITLE.agents, detail: FirstRunQuestions.placeDetail };
    case 'connect':
      return { title: ONBOARDING_TITLE.connect, detail: `The Memnox service starts by itself and ${keyTitle} becomes the key only you approve with. No account needed.` };
    case 'ask-where':
      return { title: ONBOARDING_TITLE['ask-where'], detail: 'When an agent needs a yes, Memnox asks you there first. You can add the rest later.' };
    case 'rules':
    case undefined:
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
  /** Said over the grants step, which lists only what this system asks for. */
  /** Said over who Memnox is for, which only picks what is suggested next. */
  who: 'First, who is Memnox for? Just you, you with agents working while you are away, or a team. It only picks what I suggest next.',
  /** Said over where Memnox asks, beside the key that is always on. */
  askWhere: 'Where should I ask you when an agent needs a yes? This computer is always on. Pair your phone for when you are away, or sign in to Memnox Cloud so a question reaches you in the browser or chat.',
  /** Said over the place question, where anything off this computer is offered through Memnox Cloud and never required. */
  place: 'And where does your agent run? On this computer I look after it myself. Anywhere else it reaches me through Memnox Cloud, which is optional.',
  /** Said over the last step: a pack is only proposed, and each rule waits for the person. */
  boundaries(platform: Platform): string {
    return `Last, your starting rules. The recommended ones are already chosen, and each holds once you confirm it with ${KEY_SAID[platform]} on the island. You can change any of them later.`;
  },
  /** Said on the end screen, over its one next action and what is optional. */
  done: 'That is setup done. Paste the prompt on screen into your agent, and I will ask you before the delete runs. Below it is what I can and cannot do for your agents, in plain words.',
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

/** Where the person's agent runs, the answer to the first run's second question; it only picks what is shown and said. */
export type AgentPlace = 'computer-coding' | 'computer-app' | 'hosted' | 'inside-app' | 'no-code' | 'own-code' | 'none-yet';

export interface PlaceInfo {
  readonly id: AgentPlace;
  readonly title: string;
  /** Examples a person recognises, so the right answer is found without knowing the category's name. */
  readonly detail: string;
  /** How the agent reaches Memnox, in a line. */
  readonly connects: string;
  /** Found and put under Memnox by the service on this computer, with nothing for the person to do. */
  readonly local: boolean;
  /**
   * What a connection of this kind usually comes to once it reports, for a place reached through Memnox Cloud. Only a
   * proof the service or the cloud holds ever shows more; this computer's agents show the levels the service states.
   */
  readonly expected?: CapabilityLevel;
}

export const AGENT_PLACES: readonly PlaceInfo[] = [
  { id: 'computer-coding', title: 'On this computer, for code', detail: 'Claude Code, Codex, Cursor, Gemini CLI or Windsurf.', connects: 'Memnox hooks into it on this computer by itself.', local: true },
  { id: 'computer-app', title: 'On this computer, as an app', detail: 'Claude Desktop, Hermes or OpenClaw.', connects: 'Memnox runs its tools through itself on this computer, by itself.', local: true },
  { id: 'hosted', title: 'Hosted somewhere', detail: 'Your agent on a server or in a cloud function.', connects: 'Through the Memnox guard in its code, or the Memnox gateway.', local: false, expected: 'mediated' },
  { id: 'inside-app', title: 'Inside an app you use', detail: 'An agent built into a product you use, such as a helpdesk or a CRM.', connects: 'Through an MCP address and a token, which the app calls.', local: false, expected: 'advisory' },
  { id: 'no-code', title: 'Built in a no code tool', detail: 'n8n, Zapier, Copilot Studio or a builder like them.', connects: 'Through an MCP address, added in the builder’s own steps.', local: false, expected: 'advisory' },
  { id: 'own-code', title: 'Your own code', detail: 'An agent you write yourself, in TypeScript or Python.', connects: 'Through the Memnox guard, installed from its SDK.', local: false, expected: 'mediated' },
  { id: 'none-yet', title: 'I do not have one yet', detail: 'Start from a job, and connect an agent whenever you have one.', connects: 'Nothing yet. Connect an agent whenever you are ready.', local: false },
];

const NO_PLACE: PlaceInfo = { id: 'none-yet', title: 'I do not have one yet', detail: '', connects: 'Nothing yet. Connect an agent whenever you are ready.', local: false };

export function placeInfo(place: AgentPlace): PlaceInfo {
  return AGENT_PLACES.find((each) => each.id === place) ?? NO_PLACE;
}

/** Reached through Memnox Cloud, which this computer's service cannot reach on its own. */
export function throughCloud(place: AgentPlace): boolean {
  return !placeInfo(place).local && place !== 'none-yet';
}

/** The answer already likely when the scan found agents here, so pressing Continue is the sensible thing. */
export function suggestedPlace(foundHere: number): AgentPlace | undefined {
  return foundHere > 0 ? 'computer-coding' : undefined;
}

/** The first run's questions and their words, as the Mac's `FirstRunQuestions`. */
export const FirstRunQuestions = {
  placeTitle: 'Where does your agent run?',
  placeDetail: 'Pick where the one you use most lives. You can add the others later under Agents.',
  placeCard: 'Pick one',
  reaches: 'How it reaches Memnox',
  /** What reaching an agent through Memnox Cloud asks of the person: nothing now, since signing in is optional. */
  cloudOptional: 'This kind of agent reaches Memnox through Memnox Cloud. Signing in is optional, and everything on this computer works without it.',
  /** Said where the person chose this computer and the scan found nothing yet. */
  nothingFound: 'No agent is on this computer yet. Install one and Memnox finds it and puts it under itself.',
  /** Said under the found agents once the first run put them under Memnox by itself. */
  protectedByItself: 'Memnox put the agents it found under itself, the way setup does. Nothing else was changed.',
} as const;

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
  lead: 'In plain words, for each agent, from what Memnox has seen and proved so far.',
  cannot: 'Memnox cannot see or stop anything an agent does outside the connections above, and it never acts on its own.',
  noAgents: 'No agent is connected yet, so there is nothing for Memnox to stop or see. Each one you connect shows here and under AI agents.',
  /** The agent's capabilities and seams grouped by level, strongest first, a level with nothing at it left out. */
  lines(levels: CapabilityLevels): CoverageLine[] {
    const rows = [...levelRows(levels), ...seamRows(levels)];
    return STRONGEST_FIRST.flatMap((level) => {
      const things = rows.filter((row) => row.level === level).map((row) => row.title);
      return things.length === 0 ? [] : [{ level, plain: LEVEL_WORDS[level], things, sentence: `${LEVEL_WORDS[level]}: ${joinedThings(things)}.` }];
    });
  },
  /** The line for an agent the person said runs elsewhere, until a connection of its own reports. */
  place(place: AgentPlace): string {
    const info = placeInfo(place);
    if (info.expected === undefined) return info.connects;
    return `Outside Memnox until it is connected. Connected this way, expect: ${LEVEL_WORDS[info.expected]}.`;
  },
} as const;
