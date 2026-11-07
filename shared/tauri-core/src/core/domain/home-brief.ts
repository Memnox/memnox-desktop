import { done, overview, sectionOf, type TodayItem, type TodaySources } from './today-board';

/**
 * The blocks Home reads top to bottom below the greeting, named and ordered as the console's home brief, so a person
 * moving between the two reads the same answer in the same words. The same blocks as the Mac's `HomeBrief`.
 */
export type HomeBriefBlock = 'waiting' | 'working' | 'today' | 'ready' | 'not-covered';

export const HOME_BRIEF_BLOCKS: readonly HomeBriefBlock[] = ['waiting', 'working', 'today', 'ready', 'not-covered'];

/** The blocks Home draws: Not covered is left off for now, so Home stays on what a person acts on today. */
export const HOME_BRIEF_SHOWN: readonly HomeBriefBlock[] = HOME_BRIEF_BLOCKS.filter((block) => block !== 'not-covered');

export const HOME_BRIEF_TITLE: Record<HomeBriefBlock, string> = {
  waiting: 'Waiting on you',
  working: 'Working now',
  today: 'Today',
  ready: 'Ready to hand over',
  'not-covered': 'Not covered',
};

/** What a block says while it holds nothing, so an empty block still says where things stand. */
export const HOME_BRIEF_NONE: Record<HomeBriefBlock, string> = {
  waiting: 'Nothing is waiting on you.',
  working: 'No agent is working right now.',
  today: 'Nothing was recorded today.',
  ready: 'Nothing yet. This fills in once you approve the same action a few times.',
  'not-covered': 'Every agent on this computer is under Memnox.',
};

/** Every block Home shows, in the console's order, an empty one kept so it can say so, read off the sources Today reads. */
export function homeBrief(sources: TodaySources, now: number): { block: HomeBriefBlock; items: TodayItem[] }[] {
  const board = overview(sources, now);
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
