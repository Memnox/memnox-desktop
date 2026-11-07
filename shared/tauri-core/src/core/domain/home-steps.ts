import type { HomeModeSet } from '@memnox/core/wire';

/**
 * Home's getting started steps, ported from the Mac's `HomeSteps`, which mirrors the cloud console's ladder: the
 * same stage line, the same Do this next rung, the same two tracks and the same counts won, read off this computer.
 * Every tick is a count the runtime or this computer reports, never an estimate.
 */

/** The counts the steps are read off. */
export interface HomeStanding {
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
  return mode === 'enforce' ? 'Enforcing on this computer' : 'Observing on this computer';
}

export type HomeStage = 'ungoverned' | 'observing' | 'enforcing';

export const STAGE_LABEL: Record<HomeStage, string> = {
  ungoverned: 'Nothing governed yet',
  observing: 'Observing',
  enforcing: 'Enforcing',
};

export const STAGE_MEANS: Record<HomeStage, string> = {
  ungoverned: 'No agent on this computer is under Memnox yet, so Memnox decides nothing here. Protecting them takes one press.',
  observing: 'Your agents record what a rule would have stopped, and nothing is blocked. Read a week before enforcing.',
  enforcing: 'This computer applies the verdict rather than recording it, on the rules you put in force.',
};

export type HomeTrack = 'computer' | 'work';

export const TRACKS: readonly HomeTrack[] = ['computer', 'work'];

export const TRACK_LABEL: Record<HomeTrack, string> = {
  computer: 'The agents on this computer',
  work: 'Where your work lives',
};

export const TRACK_LEAD: Record<HomeTrack, string> = {
  computer: 'Where a verdict is reached. Decided on this computer, with no network in the path.',
  work: 'What your agents can reach and start from. Linked where it is, and read on this computer.',
};

export type HomeStepId = 'protectAgents' | 'rulesInForce' | 'actionsRecorded' | 'answerAway' | 'enforce' | 'connectApps' | 'linkSource' | 'shareSkills';

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

/** Remembered, so a person who hid the steps is not shown them again on every opening. */
export const STEPS_HIDDEN_KEY = 'memnox.home.startHidden';

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
export const STEP_ROUTE: Record<HomeStepId, { readonly destination: 'agents' | 'governance' | 'settings' | 'mcp' | 'workspaces'; readonly tab: string }> = {
  protectAgents: { destination: 'agents', tab: 'list' },
  rulesInForce: { destination: 'governance', tab: 'policies' },
  actionsRecorded: { destination: 'governance', tab: 'activity' },
  enforce: { destination: 'governance', tab: 'activity' },
  answerAway: { destination: 'settings', tab: 'phones' },
  connectApps: { destination: 'mcp', tab: 'apps' },
  linkSource: { destination: 'workspaces', tab: 'sources' },
  shareSkills: { destination: 'workspaces', tab: 'skills' },
};

function homeSteps(standing: HomeStanding, keyTitle: string): HomeStep[] {
  return [
    {
      id: 'protectAgents',
      title: 'Put your agents under Memnox',
      value: 'Every agent on this computer, Claude Code through Cursor, reports to one place under one rule set.',
      how: 'Press Protect, and Memnox puts itself under each agent it found. Nothing is stopped on the first day.',
      action: 'Open Agents',
      track: 'computer',
      done: standing.agents > 0 && standing.agentsProtected === standing.agents,
      waitsOnAnAgent: false,
    },
    {
      id: 'rulesInForce',
      title: 'Let your rules reach them',
      value: 'Memnox decides on this computer with no network in the path. This is the moment it controls something rather than watching it.',
      how: `Add a ready-made pack, then confirm each rule with ${keyTitle} on the island.`,
      action: 'Add rules',
      track: 'computer',
      done: standing.rulesInForce > 0,
      waitsOnAnAgent: false,
    },
    {
      id: 'actionsRecorded',
      title: 'See what your agents actually did',
      value: "Every action, the verdict it met and the rule that decided, in one record rather than one terminal's scrollback.",
      how: 'Use an agent as you normally would. What it does shows up in Activity.',
      action: 'Open Activity',
      track: 'computer',
      done: standing.actionsRecorded > 0,
      waitsOnAnAgent: true,
    },
    {
      id: 'answerAway',
      title: 'Answer an agent without going to its terminal',
      value: 'An agent stops for a question and you answer it from the island, out loud, or from your phone when you are away.',
      how: 'Pair your phone, so a question reaches you wherever you are.',
      action: 'Pair your phone',
      track: 'computer',
      done: standing.phonesPaired > 0,
      waitsOnAnAgent: false,
    },
    {
      id: 'enforce',
      title: 'Turn this computer from watching to stopping',
      value: 'Observe mode records what it would have stopped. Enforce mode stops it. Do this once a week of the record reads right.',
      how: 'Read the record in Activity for what would have been stopped, then turn on stopping here.',
      action: 'Turn on stopping',
      track: 'computer',
      done: standing.mode === 'enforce',
      waitsOnAnAgent: false,
    },
    {
      id: 'connectApps',
      title: 'Connect the apps you work in',
      value: 'Gmail, Slack, GitHub and the rest. Agents act in them as you, and ask before anything goes out.',
      how: 'Pick an app under Connectors and sign in to it once.',
      action: 'Connect an app',
      track: 'work',
      done: standing.appsConnected > 0,
      waitsOnAnAgent: false,
    },
    {
      id: 'linkSource',
      title: 'Give your agents memory',
      value: 'Your notes and instruction files, linked where they are and read only on this computer, so every agent starts from what you know.',
      how: 'Add a folder or an instruction file as a source.',
      action: 'Add a source',
      track: 'work',
      done: standing.sourcesLinked > 0,
      waitsOnAnAgent: false,
    },
    {
      id: 'shareSkills',
      title: 'Share skills and servers across agents',
      value: "Kept once in Memnox and written into each agent's own format, so one added once reaches every agent you choose.",
      how: 'Bring in the skills your agents already keep, then give them to the agents you choose.',
      action: 'Open Skills',
      track: 'work',
      done: standing.skillsShared + standing.serversShared > 0,
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
