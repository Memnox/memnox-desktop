import type { LocalArmsReads, WorkspaceGraphView } from './memory-arms/arms-local';
import type { MemoryMap } from './memory-arms/arms-node';
import type { MemoryStatusName } from './memory-lines';

/**
 * What the brain's overlay says and which of memory it draws, word for word the Mac's `MemoryDestination` and
 * `MemoryMapView`: the "Whose memory" chips, the heading over the brain with its three counts, and the count of
 * points in view over the view's controls. "This Mac" is "This computer" here, the one word the platform changes.
 */

/** Whose memory the brain draws: everything, this computer's alone, or what came down from the workspace. */
export type MemoryHomeFilter = 'everything' | 'thisComputer' | 'workspace';

/** The "Whose memory" chips, in the order they stand. */
export const MEMORY_HOME_FILTERS: readonly { filter: MemoryHomeFilter; label: string }[] = [
  { filter: 'everything', label: 'Everything' },
  { filter: 'thisComputer', label: 'This computer' },
  { filter: 'workspace', label: 'Workspace' },
];

/** Where the chosen chip is remembered for the next visit, the Mac's own key. */
export const MEMORY_HOME_KEY = 'memnox.memory.home';

/** The chip a stored value names, everything when nothing or something unknown was stored. */
export function homeFilterOf(stored: string | null): MemoryHomeFilter {
  if (stored === 'thisMac') return 'thisComputer';
  return MEMORY_HOME_FILTERS.find((each) => each.filter === stored)?.filter ?? 'everything';
}

/** The heading over the brain, as the Mac's `BrainHeading` writes it. */
export const BRAIN_HEADING = {
  overline: 'WHAT YOUR AGENTS KNOW',
  title: 'Every memory.',
  titleQuiet: 'Connected.',
  subline: 'Skills at the core, memory in a sector to each area, the rules that run without you in a ring, and your applications around the outside.',
  memories: 'MEMORIES',
  sources: 'SOURCES',
  connections: 'CONNECTIONS',
} as const;

/** The count over the view's controls, in the Mac's capitals. */
export function inViewLine(count: number): string {
  return `${count} ${count === 1 ? 'POINT' : 'POINTS'} IN VIEW`;
}

/**
 * The heading's three counts, read as the Mac's `MemoryGroups.stats` reads them: the memories, the apps memory came
 * through, which this map holds as tiles round the outside rather than as nodes, and every line.
 */
export function brainStats(map: MemoryMap, apps: number): { memories: number; sources: number; connections: number } {
  const memories = map.nodes.filter((node) => node.kind === 'memory').length;
  return { memories, sources: apps, connections: map.edges.length };
}

type WorkspaceNode = WorkspaceGraphView['nodes'][number];

/**
 * Whether a workspace node is drawn under the status chip: a decision only under its own standing, a rule set in force
 * as verified, and what arrived under every chip, as the Mac's `WorkspaceLiveLines.shows` decides it.
 */
export function workspaceShows(node: WorkspaceNode, status: MemoryStatusName | undefined): boolean {
  if (status === undefined) return true;
  switch (node.kind) {
    case 'decision':
    case 'candidate': {
      const standing = node.status === 'verified' || node.status === 'candidate' ? node.status : undefined;
      return standing === status;
    }
    case 'policy':
      return status === 'verified';
    default:
      return true;
  }
}

/**
 * The reads the brain is built from under the chips: this computer's own reads without the workspace, the workspace
 * alone, or both, with the workspace's decisions narrowed to the status chip. Only lines between drawn nodes stay.
 */
export function heldReads(reads: LocalArmsReads, home: MemoryHomeFilter, status: MemoryStatusName | undefined): LocalArmsReads {
  const workspace =
    reads.workspace === undefined ? undefined : { ...reads.workspace, nodes: reads.workspace.nodes.filter((node) => workspaceShows(node, status)) };
  switch (home) {
    case 'everything':
      return { ...reads, ...(workspace === undefined ? {} : { workspace }) };
    case 'thisComputer': {
      const { workspace: _left, ...local } = reads;
      return local;
    }
    case 'workspace':
      return workspace === undefined ? {} : { workspace };
  }
}

/** The brain map's own controls and card, in the words the Mac's brain says them. */
export const ArmsLines = {
  motion: 'Motion',
  motionSpeed: 'Motion speed',
  speed: (speed: number) => `${speed}x`,
  replay: 'Replay the opening',
  view: 'View',
  search: 'Search the brain',
  searchPlaceholder: 'SEARCH THE BRAIN',
  closeSearch: 'Close the search',
  noMatches: 'NO MATCHES',
  matches: (count: number) => `${count} ${count === 1 ? 'MATCH' : 'MATCHES'} · ENTER OPENS`,
  zoomOut: 'Zoom out',
  fit: 'Fit',
  zoomIn: 'Zoom in',
  showArea: 'Show only this area',
  close: 'Close',
  holds: (count: number) => `Holds ${count}`,
  linked: 'Linked',
  openSkills: 'Open My Skills',
  openRules: 'Open Rules',
  openConnectors: 'Open Connectors',
  andMore: (count: number) => `and ${count} more`,
} as const;
