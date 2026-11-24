import { done, overview, sectionOf, type TodayItem, type TodaySources } from './today-board';

/**
 * The blocks Home reads top to bottom below the greeting, named and ordered as `shared/ux/contract.json` lists them
 * for the console, the Mac, Windows and Linux. The same blocks as the Mac's `HomeBrief`.
 */
export type HomeBriefBlock = 'waiting' | 'working' | 'ready' | 'today' | 'not-covered';

export const HOME_BRIEF_BLOCKS: readonly HomeBriefBlock[] = ['waiting', 'working', 'ready', 'today', 'not-covered'];

/** The blocks Home draws: Not covered is left off for now, so Home stays on what a person acts on today. */
export const HOME_BRIEF_SHOWN: readonly HomeBriefBlock[] = HOME_BRIEF_BLOCKS.filter((block) => block !== 'not-covered');

export const HOME_BRIEF_TITLE: Record<HomeBriefBlock, string> = {
  waiting: 'Needs you',
  working: 'Working now',
  ready: 'You could let go of',
  today: 'Today',
  'not-covered': 'Not covered',
};

/** What a block says while it holds nothing, so an empty block still says where things stand. */
export const HOME_BRIEF_NONE: Record<HomeBriefBlock, string> = {
  waiting: 'Nothing needs you. Agents keep working inside their rules.',
  working: 'No agent is working right now.',
  today: 'Nothing was recorded today.',
  ready: 'Nothing yet. Once you say yes to the same thing a few times, Memnox offers to stop asking.',
  'not-covered': 'Every agent on this computer is under Memnox.',
};

/** Every block Home shows, in the console's order, an empty one kept so it can say so, read off the sources Today reads. */
/**
 * With a project chosen in the picker, what waits and what works is only that project's, while what only the person
 * owes and what they could let go of stay, since neither belongs to one project; Today is narrowed where it is read.
 */
export function homeBrief(sources: TodaySources, now: number, project?: string): { block: HomeBriefBlock; items: TodayItem[] }[] {
  const board = overview(sources, now).filter(
    (item) => project === undefined || item.kind.kind === 'hand-over' || item.kind.kind === 'owed' || item.project === project,
  );
  const of = (block: HomeBriefBlock): TodayItem[] => {
    switch (block) {
      // What only the person can do waits on them as much as a held call does.
      case 'waiting':
        return board.filter((item) => sectionOf(item) === 'needs-you' || item.kind.kind === 'owed');
      case 'working':
        return board.filter((item) => item.kind.kind === 'working');
      case 'today':
        return done(sources.activity, now);
      case 'ready':
        return board.filter((item) => item.kind.kind === 'hand-over');
      case 'not-covered':
        return board.filter((item) => item.kind.kind === 'unprotected');
    }
  };
  return HOME_BRIEF_SHOWN.map((block) => ({ block, items: of(block) }));
}

/** The items in the order the blocks draw them, which is the order Up and Down step through. */
export function briefItems(blocks: readonly { items: readonly TodayItem[] }[]): TodayItem[] {
  return blocks.flatMap((each) => each.items);
}

/**
 * Home's first sentence, so a person who reads nothing else still knows where things stand:
 * "3 agents working. 1 needs you. Nothing was stopped today." Ported from the Mac's `HomeOpener`.
 */
export function homeOpener(working: number, needsYou: number, stoppedToday: number): string {
  const busy = working === 0 ? 'No agent is working right now.' : working === 1 ? '1 agent working.' : `${working} agents working.`;
  const waiting = needsYou === 0 ? 'Nothing needs you.' : `${needsYou} ${needsYou === 1 ? 'needs' : 'need'} you.`;
  const stopped =
    stoppedToday === 0
      ? 'Nothing was stopped today.'
      : `Memnox stopped ${stoppedToday} risky ${stoppedToday === 1 ? 'action' : 'actions'} today.`;
  return [busy, waiting, stopped].join(' ');
}

/** The same sentence read off Home's blocks, counting each working agent once. */
export function homeOpenerOf(blocks: readonly { block: HomeBriefBlock; items: readonly TodayItem[] }[], stoppedToday: number): string {
  const items = (block: HomeBriefBlock) => blocks.find((each) => each.block === block)?.items ?? [];
  const agents = new Set(items('working').map((item) => item.agent ?? item.agentName));
  return homeOpener(agents.size, items('waiting').length, stoppedToday);
}
