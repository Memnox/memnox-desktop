import type { MemorySourceView } from '@memnox/core/wire';
import type { LocalArmsReads, WorkspaceGraphView } from './memory-arms/arms-local';
import type { MemoryMap } from './memory-arms/arms-node';
import type { LegendLayer } from './memory-arms/arms-legend';
import { sectionNumber, TOUR_LENGTH, TOUR_SECTIONS, type TourPart } from './memory-arms/arms-tour';
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
  search: 'Search the brain',
  searchPlaceholder: 'SEARCH THE BRAIN',
  closeSearch: 'Close the search',
  noMatches: 'NO MATCHES',
  matches: (count: number) => `${count} ${count === 1 ? 'MATCH' : 'MATCHES'} · ENTER OPENS`,
  showArea: 'Show only this area',
  close: 'Close',
  holds: (count: number) => `Holds ${count}`,
  linked: 'Linked',
  openSkills: 'Open My Skills',
  openRules: 'Open Rules',
  openConnectors: 'Open Connectors',
  andMore: (count: number) => `and ${count} more`,
} as const;

/** A count with its noun, one or many, in the Mac's `BrainWords.counted`. */
export function counted(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}

/** The brain's keys, the Mac's `BrainWords` and `MapWords` keys, each pressed while no field has the cursor. */
export const BRAIN_KEYS = {
  replay: 'R',
  tour: 'T',
  motion: 'M',
  search: '/',
  fit: 'F',
  center: 'C',
  pause: 'Space',
} as const;

/** The overlays along the brain's foot, word for word the Mac's `MemoryMapView`. */
export const BrainFootLines = {
  leftHint: 'Drag to pan · Scroll to zoom · 1 2 3 switch views',
  orbsHint: 'Drag to orbit · Arrows fly node to node · Click turns it to you · Scroll to zoom',
  rightHint: 'Space for Motion · / to search · Double click to fit',
  search: 'Search',
  searchHelp: `Search the brain, or press ${BRAIN_KEYS.search}`,
  replay: 'Replay',
  replayHelp: `Fly the layers in again from the core outward, or press ${BRAIN_KEYS.replay}`,
  cinema: 'Cinema',
  cinemaHelp: 'Hide everything but the brain; Escape brings it back',
  tour: 'Tour',
  tourHelp: `Take the brain apart layer by layer and put it back, or press ${BRAIN_KEYS.tour}`,
  tourStill: 'The tour moves the brain, so it waits while Reduce Motion is on',
  leaveCinema: 'Press Escape to leave Cinema',
  zoom: 'Zoom',
  zoomOut: 'Zoom out',
  fit: 'Fit',
  fitHelp: `Fit the whole brain on screen, or press ${BRAIN_KEYS.fit}`,
  zoomIn: 'Zoom in',
  /** The growth card: how many memories, and how many are verified. */
  inTheBrain: (total: number) => counted(total, 'memory in the brain', 'memories in the brain'),
  verified: (verified: number, total: number) => `${verified} verified, ${total - verified} still to settle`,
  /** Said in the middle once the legend has taken everything off. */
  nothingNeedsYou: 'Nothing here needs your attention.',
  everythingHidden: 'Everything is hidden. Turn an area back on in the legend.',
} as const;

/** The legend's words, the Mac's `BrainLegend`. */
export const BrainLegendLines = {
  label: 'Areas and layers',
  areas: 'MEMORY AREAS',
  layers: 'LAYERS',
  lights: 'Lights its sector on the brain',
  lit: 'Lit',
  hide: (name: string) => `Hide ${name}`,
  show: (name: string) => `Show ${name}`,
  /** Routines are not something Memnox runs yet, so the band says what runs without the person today. */
  routinesLater: 'Routines come later; this ring holds the rules and standing permissions that run without you today.',
  attentionOnly: 'Only what needs attention',
  allLabels: 'Show all labels',
  on: 'On',
  off: 'Off',
} as const;

/** A layer said in a sentence, for the legend. */
export function layerWord(layer: LegendLayer): string {
  switch (layer) {
    case 'skill':
      return 'Skills';
    case 'rule':
      return 'Rules';
    case 'app':
      return 'Applications';
  }
}

/** The tour's deck, an instrument's operation log, in the Mac's `BrainTourDeck` words. */
export const TourLines = {
  overline: 'TOUR · OPERATING MODE',
  label: 'Tour',
  rail: 'CLICK OR DRAG THE RAIL',
  time: 'Tour time',
  leave: 'Leave the tour',
  leaveHelp: 'Leave the tour, or press Escape',
  pause: 'Pause the tour',
  play: 'Play the tour',
  pauseHelp: 'Hold the tour, or press Space',
  playHelp: 'Run the tour on, or press Space',
  /** Which stretch it is of how many, two digits each. */
  count: (seconds: number) => `${twoDigits(sectionNumber(seconds))} / ${twoDigits(TOUR_SECTIONS.length)}`,
  /** Where the playhead is of the whole loop, in whole seconds. */
  clock: (playhead: number) => `00:${twoDigits(Math.floor(playhead))} / 00:${twoDigits(TOUR_LENGTH)}`,
  timeValue: (playhead: number) => `${Math.floor(playhead)} of ${TOUR_LENGTH} seconds`,
} as const;

function twoDigits(value: number): string {
  return String(value).padStart(2, '0');
}

/** What each stretch of the tour is called on its deck, as an instrument names a mode. */
export function tourName(part: TourPart): string {
  switch (part) {
    case 'assembled':
      return 'ASSEMBLED';
    case 'core':
      return 'CORE OPEN';
    case 'areas':
      return 'AREAS OPEN';
    case 'rules':
      return 'RULES OUT';
    case 'applications':
      return 'APPLICATIONS OUT';
    case 'teardown':
      return 'TEARDOWN';
    case 'reassembly':
      return 'REASSEMBLY';
  }
}

/** The line under a stretch's name, counting what it opened. */
export function tourDetail(part: TourPart, counts: { skills: number; areas: number; rules: number; applications: number; marks: number }): string {
  switch (part) {
    case 'assembled':
      return 'EVERY LAYER IN PLACE';
    case 'core':
      return `${counted(counts.skills, 'FILE', 'FILES')} · SPREAD FROM THE MIDDLE`;
    case 'areas':
      return `${counted(counts.areas, 'AREA', 'AREAS')} · SLID OUT FROM THE CORE`;
    case 'rules':
      return `${counted(counts.rules, 'RULE', 'RULES')} · RING TELESCOPED OUT`;
    case 'applications':
      return `${counted(counts.applications, 'APPLICATION', 'APPLICATIONS')} · TILES OUT`;
    case 'teardown':
      return `${counted(counts.marks, 'MARK', 'MARKS')} APART · TURNTABLE`;
    case 'reassembly':
      return 'TURNTABLE · RETURNING';
  }
}

/**
 * How much of what was learned is verified, the Mac's `MemoryGroups.growth`: off the sources' own counts, which every
 * status adds to whatever the page filters, and off the map's facts where no source counted any.
 */
export function brainGrowth(sources: readonly Pick<MemorySourceView, 'counts'>[], map: MemoryMap): { verified: number; total: number } {
  const total = sources.reduce((sum, { counts }) => sum + counts.candidate + counts.verified + counts.conflicting + counts.outdated + counts.rejected, 0);
  if (total > 0) return { verified: sources.reduce((sum, { counts }) => sum + counts.verified, 0), total };
  const facts = map.nodes.filter((node) => node.kind === 'memory');
  return { verified: facts.filter((node) => node.status === 'settled').length, total: facts.length };
}

/** The day of a timestamp, as the Mac cuts it off the front. */
const DAY_LENGTH = 10;

/**
 * The workspace's lines under the heading's counts, the Mac's `workspaceFoot` read off the workspace's graph: how a
 * computer not in a workspace joins one, where the picture came from, when it was pulled, and what was kept back.
 */
export function workspaceFoot(graph: Pick<WorkspaceGraphView, 'source' | 'fallback' | 'withheld' | 'syncedAt'>): { lines: string[]; join: boolean } {
  if (graph.fallback === 'not-joined') return { lines: [WorkspaceFootLines.notJoined], join: true };
  const lines: string[] = [];
  const source = workspaceSourceLine(graph);
  if (source !== undefined) lines.push(source);
  if (graph.source !== 'live' && graph.syncedAt !== undefined && graph.syncedAt !== '') lines.push(WorkspaceFootLines.pulled(graph.syncedAt.slice(0, DAY_LENGTH)));
  if (graph.withheld > 0) lines.push(WorkspaceFootLines.withheld(graph.withheld));
  return { lines, join: false };
}

/** Where the workspace's picture came from, the Mac's `WorkspaceLiveLines.sourceLine`. */
function workspaceSourceLine(graph: Pick<WorkspaceGraphView, 'source' | 'fallback'>): string | undefined {
  if (graph.source === 'live') return WorkspaceFootLines.live;
  switch (graph.fallback) {
    case 'unreachable':
      return WorkspaceFootLines.unreachable;
    case 'refused':
      return WorkspaceFootLines.refused;
    case 'not-joined':
      return undefined;
    default:
      return WorkspaceFootLines.saved;
  }
}

/** The workspace foot's words, with "this Mac" said as "this computer". */
export const WorkspaceFootLines = {
  notJoined: 'This computer is not joined to a workspace. Sign in and join one under Account to see what your team settled beside what this computer learned.',
  openAccount: 'Open Account',
  refresh: 'Refresh from your workspace',
  live: 'Read live from your workspace',
  unreachable: 'Showing saved facts, the cloud could not be reached.',
  refused: 'Showing saved facts, your workspace did not answer this computer.',
  saved: 'Showing saved facts.',
  pulled: (day: string) => `Pulled from your workspace ${day}`,
  withheld: (count: number) => (count === 1 ? '1 more your workspace keeps from this computer.' : `${count} more your workspace keeps from this computer.`),
} as const;

/** The brain's three views, in the order 1 2 3 picks them, with the Mac's `BrainMode` titles. */
export const BRAIN_VIEWS = [
  { mode: 'brain', title: 'Brain map' },
  { mode: 'orbs', title: '3D orbs' },
  { mode: 'timeline', title: 'Timeline' },
] as const;

/** The view's own controls along the top right, the Mac's `BrainViewControls`. */
export const BrainViewLines = {
  label: 'View controls',
  motion: (on: boolean) => `Motion ${on ? 'on' : 'off'}, or press ${BRAIN_KEYS.pause}`,
  speed: 'Speed',
  motionSpeed: 'Motion speed',
} as const;

/** How slow and how quick the idle life can run, the Mac's `BrainMotion.slowest` and `quickest`. */
export const BRAIN_SPEED = { slowest: 0.25, quickest: 3, normal: 1 } as const;
