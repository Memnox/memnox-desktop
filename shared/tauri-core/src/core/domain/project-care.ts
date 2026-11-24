import type { PolicyRuleView } from '@memnox/core/wire';
import { CARE, type CareLevel } from './onboarding';

/**
 * How careful agents are inside one project, read off the rules that hold there, as the Mac's `ProjectCare`: none of
 * its own is Relaxed, the safe defaults started here is Careful, and the read-only pack started here is Strict.
 */
export type ProjectCare = 'relaxed' | 'careful' | 'strict';

export const PROJECT_CARES: readonly ProjectCare[] = ['relaxed', 'careful', 'strict'];

export const PROJECT_CARE: Readonly<Record<ProjectCare, { readonly label: string; readonly line: string; readonly level?: CareLevel }>> = {
  relaxed: { label: 'Relaxed', line: 'Agents here follow your general rules and nothing more.' },
  careful: { label: 'Careful', line: "Agents here wait for you before they delete, publish or change somebody else's system.", level: 'ask' },
  strict: { label: 'Strict', line: 'Agents here wait for you before they change anything.', level: 'strict' },
};

/** The pack a level of care starts, by the shipped pack's id; Relaxed starts none. */
export function carePack(care: ProjectCare): string | undefined {
  const level = PROJECT_CARE[care].level;
  return level === undefined ? undefined : CARE[level].pack;
}

/** The strictest pack started here wins, read off the name the runtime gives every rule it imports from one. */
export function projectCareOf(rulesHere: readonly Pick<PolicyRuleView, 'name'>[]): ProjectCare {
  const started = (care: ProjectCare) => {
    const pack = carePack(care);
    return pack !== undefined && rulesHere.some((rule) => rule.name.startsWith(`pack-${pack}-`));
  };
  if (started('strict')) return 'strict';
  if (started('careful')) return 'careful';
  return 'relaxed';
}

/** A project shown before any exists, so the value of keeping work apart is seen before a folder is chosen. */
export interface ProjectExample {
  readonly name: string;
  readonly care: ProjectCare;
  readonly line: string;
}

export const PROJECT_EXAMPLES: readonly ProjectExample[] = [
  { name: 'Website', care: 'relaxed', line: 'Agents fix copy and pages freely.' },
  { name: 'Support inbox', care: 'careful', line: 'Agents draft replies and wait for you before anything is sent.' },
  { name: 'Invoicing', care: 'strict', line: 'Every change waits for you.' },
];

/** Why a project is worth having, said on the empty Projects page in words anybody uses, as the Mac's `ProjectWhy`. */
export const ProjectWhy = {
  title: 'Keep each piece of work apart',
  lead: 'A project is one piece of work your agents help with, such as your website, invoicing or the support inbox.',
  lines: [
    'Its own care: the website stays relaxed while invoicing waits for you.',
    'Its own memory: agents there already know what was decided, so you stop repeating yourself.',
    'Its own story: ask what happened in invoicing this week, not in everything at once.',
    'Its own people: see who is on what, and catch two agents changing the same thing.',
  ],
  examplesTitle: 'Start from an example',
  start: 'Start like this',
  careTitle: 'How careful agents are here',
  makeIt: (care: ProjectCare) => `Make it ${PROJECT_CARE[care].label.toLowerCase()}`,
  nowTitle: 'Right now',
  nobodyWorking: 'No agent is working here right now',
  nothingWaits: 'Nothing waits for you here',
  waits: (count: number) => (count === 1 ? '1 thing waits for you here' : `${count} things wait for you here`),
  waitsHow: 'Answer it on the island or under Needs you.',
  eachRuleWaits: 'Each rule waits for your signature on the island.',
} as const;
