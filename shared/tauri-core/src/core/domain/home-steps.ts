import type { HomeModeSet } from '@memnox/core/wire';
import type { Route } from './destinations';

/**
 * Home's getting started steps, ported from the Mac's `HomeSteps`, which mirrors the cloud console's ladder: the
 * same stage line, the same Get set up rung, the same tracks and the same counts won, read off this computer.
 * Every tick is a count the runtime or this computer reports, never an estimate.
 */

/** The counts the steps are read off. */
export interface HomeStanding {
  /** Whether the two onboarding steps were finished, which is the first rung until they are. */
  readonly setupFinished: boolean;
  readonly agents: number;
  readonly agentsProtected: number;
  readonly rulesInForce: number;
  readonly actionsRecorded: number;
  readonly phonesPaired: number;
  /** Whether the runtime said it enforces rather than observes; undefined before it answered. */
  readonly mode: HomeMode | undefined;
  readonly appsConnected: number;
  readonly sourcesLinked: number;
  readonly skillsShared: number;
  readonly serversShared: number;
}

export const EMPTY_STANDING: HomeStanding = {
  setupFinished: true,
  agents: 0,
  agentsProtected: 0,
  rulesInForce: 0,
  actionsRecorded: 0,
  phonesPaired: 0,
  mode: undefined,
  appsConnected: 0,
  sourcesLinked: 0,
  skillsShared: 0,
  serversShared: 0,
};

export type HomeMode = 'observe' | 'enforce';

/** The mode the home names, or undefined for a word this app does not know. */
export function homeMode(word: string | undefined): HomeMode | undefined {
  return word === 'observe' || word === 'enforce' ? word : undefined;
}

/** The badge beside Home's greeting, so the mode the runtime reported is read at a glance. */
export function modeBadge(mode: HomeMode): string {
  return mode === 'enforce' ? 'Protecting' : 'Watching only';
}

export type HomeStage = 'ungoverned' | 'observing' | 'enforcing';

export const STAGE_LABEL: Record<HomeStage, string> = {
  ungoverned: 'Not set up yet',
  observing: 'Watching only',
  enforcing: 'Protecting',
};

export const STAGE_MEANS: Record<HomeStage, string> = {
  ungoverned: 'Memnox cannot see your agents yet. Connecting them takes one press, and nothing is stopped.',
  observing: 'Memnox writes down what your agents do and stops nothing yet.',
  enforcing: 'Memnox stops anything risky until you say yes, and lets the rest run.',
};

export type HomeTrack = 'computer' | 'work';

export const TRACKS: readonly HomeTrack[] = ['computer', 'work'];

export const TRACK_LABEL: Record<HomeTrack, string> = {
  computer: 'Your agents',
  work: 'Where your work lives',
};

export const TRACK_LEAD: Record<HomeTrack, string> = {
  computer: 'What Memnox sees and stops, decided on this computer with no network in the path.',
  work: 'What your agents can reach and start from. Linked where it is, and read on this computer.',
};

/** Three at most, so getting started never reads as a project. */
export type HomeStepId = 'protectAgents' | 'chooseCare' | 'answerAway';

export interface HomeStep {
  readonly id: HomeStepId;
  readonly title: string;
  /** What it gives, in the person's terms, never what it costs. */
  readonly value: string;
  readonly how: string;
  /** The one press that moves it on. */
  readonly action: string;
  readonly track: HomeTrack;
  readonly done: boolean;
  /** True where nobody can hurry it, such as an agent doing something for the record to hold. */
  readonly waitsOnAnAgent: boolean;
}

export interface HomeCount {
  readonly label: string;
  readonly count: number;
}

export interface HomeSetup {
  readonly stage: HomeStage;
  readonly steps: readonly HomeStep[];
  /** The first unfinished step the person can go and do; undefined once only waits are left. */
  readonly next: HomeStep | undefined;
  readonly waiting: readonly HomeStep[];
  readonly standing: readonly HomeCount[];
  readonly completed: number;
  /** Nothing left at all, waits included, which is when Home stops showing the steps. */
  readonly climbed: boolean;
}

export const WAITING_LABEL = 'Waiting on an agent';
export const WAITING_MEANS = 'This closes the first time an agent on this computer does something. Use one as you normally would.';

/** The card's title on every surface, from the contract's Home block of that name. */
export const CARD_TITLE = 'Get set up';
export const ALL_STEPS = 'Show all steps';
export const FEWER_STEPS = 'Show fewer steps';

export function homeSetup(standing: HomeStanding, keyTitle: string): HomeSetup {
  const steps = homeSteps(standing, keyTitle);
  const open = steps.filter((step) => !step.done);
  const next = open.find((step) => !step.waitsOnAnAgent);
  const waiting = open.filter((step) => step.waitsOnAnAgent);
  return {
    stage: stageOf(standing),
    steps,
    next,
    waiting,
    standing: won(standing),
    completed: steps.filter((step) => step.done).length,
    climbed: next === undefined && waiting.length === 0,
  };
}

/** The steps of one track that are neither the next one nor waiting, since those are drawn above the tracks. */
export function restOf(setup: HomeSetup, track: HomeTrack): readonly HomeStep[] {
  return setup.steps.filter((step) => step.track === track && step.id !== setup.next?.id && !setup.waiting.some((each) => each.id === step.id));
}

/** "3 of 8 done", beside the stage as the cloud counts it. */
export function progressLine(setup: HomeSetup): string {
  return `${setup.completed} of ${setup.steps.length} done`;
}

export function stageOf(standing: HomeStanding): HomeStage {
  if (standing.agentsProtected === 0) return 'ungoverned';
  return standing.mode === 'enforce' ? 'enforcing' : 'observing';
}

/** Where each step's press goes in the window; for stopping, that is the record it is read off. */
export const STEP_ROUTE: Record<HomeStepId, Route & { readonly tab: string }> = {
  protectAgents: { destination: 'agents', tab: 'agents' },
  chooseCare: { destination: 'rules', tab: 'rules' },
  answerAway: { destination: 'settings', tab: 'phones' },
};

function homeSteps(standing: HomeStanding, keyTitle: string): HomeStep[] {
  return [
    {
      id: 'protectAgents',
      title: 'Connect your agents',
      value: 'Memnox sees what each agent does and can stop what is risky, from Claude Code to Cursor.',
      how: 'Press Connect, and Memnox puts itself beside each agent it found. Nothing is stopped yet.',
      action: 'Open Agents',
      track: 'computer',
      done: standing.agents > 0 && standing.agentsProtected === standing.agents,
      waitsOnAnAgent: false,
    },
    {
      id: 'chooseCare',
      title: 'Choose how careful Memnox is',
      value: 'Just watch, ask before risky things, or ask about almost everything. You can change it any time.',
      how: `Pick one, then confirm each rule with ${keyTitle} on the island.`,
      action: 'Choose',
      track: 'computer',
      done: standing.setupFinished || standing.rulesInForce > 0,
      waitsOnAnAgent: false,
    },
    {
      id: 'answerAway',
      title: 'Answer from your phone',
      value: 'When an agent waits for you and you are away, the question reaches your phone and you answer there.',
      how: 'Pair your phone once.',
      action: 'Pair your phone',
      track: 'computer',
      done: standing.phonesPaired > 0,
      waitsOnAnAgent: false,
    },
  ];
}

/** Only the counts above zero, in the order a computer earns them. */
function won(standing: HomeStanding): HomeCount[] {
  const all: HomeCount[] = [
    { label: 'Agents protected', count: standing.agentsProtected },
    { label: 'Rules in force', count: standing.rulesInForce },
    { label: 'Actions recorded', count: standing.actionsRecorded },
    { label: 'Phones paired', count: standing.phonesPaired },
    { label: 'Apps connected', count: standing.appsConnected },
    { label: 'Sources linked', count: standing.sourcesLinked },
    { label: 'Skills shared', count: standing.skillsShared },
    { label: 'Servers shared', count: standing.serversShared },
  ];
  return all.filter((each) => each.count > 0);
}

/** What asking the runtime to stop rather than watch came to. */
export type EnforceOutcome = { kind: 'enforcing'; set: HomeModeSet } | { kind: 'refused'; why: string } | { kind: 'unreachable' };

/**
 * The words around turning this computer from watching to stopping, ported from the Mac's `HomeEnforce`. Only ever
 * toward enforce, since it narrows what agents may do; going back widens and stays at the terminal.
 */
export const HomeEnforce = {
  title: 'Turn on stopping?',
  message: 'Today this computer records what a rule would have stopped and lets it run. From now on, what a rule denies is stopped, and what a rule asks about waits for you.',
  detail: 'The record in Activity shows what would have been stopped so far, so you can read it first.',
  confirm: 'Turn on stopping',
  readFirst: 'Read the record first',
  older: 'This Memnox is older than the app, so run memnox protect --enforce in a terminal',

  /** The line under the step once the runtime answered, saying where the mode went and how to put it back. */
  line(outcome: EnforceOutcome): string {
    switch (outcome.kind) {
      case 'enforcing':
        return outcome.set.was === outcome.set.now
          ? 'This computer was already stopping what a rule denies.'
          : 'This computer now stops what a rule denies. memnox protect --observe in a terminal puts it back.';
      case 'refused':
        return outcome.why;
      case 'unreachable':
        return 'Memnox did not answer. Check that it is running, then try again.';
    }
  },
};
