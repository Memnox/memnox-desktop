/**
 * What the brain map is drawn from, the same shape the cloud console's memory map hands its ARMS view, so the
 * port of `memnox-client/apps/app/components/memory/map/arms` reads one record on either side. The desktop builds
 * it from the daemon's reads in `arms-local.ts`; nothing here is laid out, since the brain places every piece itself.
 */

/** What a node on the map is. A `document` arrived on its own; a `passage` is a piece of one. */
export const MEMORY_NODE_KINDS = ['memory', 'document', 'passage', 'person', 'group', 'policy', 'conversation'] as const;
export type MemoryNodeKind = (typeof MEMORY_NODE_KINDS)[number];

/** Where one memory stands right now, as the cloud's map words it. */
export type MemoryStatus = 'recent' | 'settled' | 'expiring' | 'forgotten';

/** How a source reached memory: a file somebody added, a thing a connected system delivered, or a link. */
export type SourceOrigin = 'uploaded' | 'connected' | 'linked';

/** One message an author posted that is counted rather than drawn. */
export interface SaidMessage {
  readonly ref: string;
  readonly label: string;
  readonly href?: string;
  readonly excerpt?: string;
  /** Epoch milliseconds. */
  readonly at?: number;
}

export interface MemoryMapNode {
  readonly id: string;
  readonly label: string;
  readonly kind: MemoryNodeKind;
  /** The memory's own words, verbatim. */
  readonly statement?: string;
  readonly status?: MemoryStatus;
  /** What the document is, or where the memory stands. */
  readonly detail?: string;
  /** Where the evidence lives, a link or a path on this computer. */
  readonly href?: string;
  readonly origin?: SourceOrigin;
  readonly excerpt?: string;
  /** The system that delivered it (`slack`, `github`, `claude`), worn as a mark and grouping it into an area. */
  readonly system?: string;
  readonly repeats?: number;
  readonly messages?: number;
  /** True for an app rather than a person. */
  readonly app?: boolean;
  readonly said?: readonly SaidMessage[];
}

/** What one line says, each a field on the record. */
export interface MemoryMapEdge {
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly kind: string;
}

export interface MemoryMap {
  readonly nodes: readonly MemoryMapNode[];
  readonly edges: readonly MemoryMapEdge[];
}

/** The product a slug names, the way its own makers spell it. */
const NAMES: Readonly<Record<string, string>> = {
  github: 'GitHub',
  gitlab: 'GitLab',
  bitbucket: 'Bitbucket',
  slack: 'Slack',
  notion: 'Notion',
  linear: 'Linear',
  figma: 'Figma',
  jira: 'Jira',
  zendesk: 'Zendesk',
  googledocs: 'Google Docs',
  googledrive: 'Google Drive',
  gmail: 'Gmail',
  googlemeet: 'Google Meet',
  googlecalendar: 'Google Calendar',
  zoom: 'Zoom',
  dropbox: 'Dropbox',
  asana: 'Asana',
  trello: 'Trello',
  monday: 'monday.com',
  intercom: 'Intercom',
  hubspot: 'HubSpot',
  salesforce: 'Salesforce',
  sentry: 'Sentry',
  pagerduty: 'PagerDuty',
  confluence: 'Confluence',
  clickup: 'ClickUp',
  discord: 'Discord',
  claude: 'Claude',
  codex: 'Codex',
  cursor: 'Cursor',
  obsidian: 'Obsidian',
  supermemory: 'Supermemory',
  mcp: 'MCP',
  notes: 'Notes',
  instructions: 'Instructions',
  apps: 'Apps',
};

/** A system's name for a reader, or its slug capitalised where it is not listed. */
export function systemName(slug: string): string {
  return NAMES[slug] ?? slug.charAt(0).toUpperCase() + slug.slice(1);
}

/** FNV 1a, 32 bit: a fast, stable string hash, the one the cloud's brain places by. */
const FNV_OFFSET_BASIS = 2166136261;
const FNV_PRIME = 16777619;
export function hashOf(text: string): number {
  let hash = FNV_OFFSET_BASIS;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, FNV_PRIME);
  }
  return hash >>> 0;
}

/** Mulberry32's own constants. */
const MULBERRY_STEP = 0x6d2b79f5;
const MULBERRY_SHIFT_A = 15;
const MULBERRY_SHIFT_B = 7;
const MULBERRY_SHIFT_C = 14;
const MULBERRY_OR = 61;
const UINT32_RANGE = 4294967296;

export type Random = () => number;

/** Mulberry32: a small seeded generator, the same run of numbers for the same seed. */
export function seededRandom(seed: number): Random {
  let state = seed >>> 0;
  return () => {
    state = (state + MULBERRY_STEP) >>> 0;
    let mixed = state;
    mixed = Math.imul(mixed ^ (mixed >>> MULBERRY_SHIFT_A), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> MULBERRY_SHIFT_B), mixed | MULBERRY_OR);
    return ((mixed ^ (mixed >>> MULBERRY_SHIFT_C)) >>> 0) / UINT32_RANGE;
  };
}
