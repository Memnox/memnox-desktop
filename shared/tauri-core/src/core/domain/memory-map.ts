import type { MemoryItemView, MemorySourceView } from '@memnox/core/wire';
import { centred, fan, at, START, type Placed } from './surface-geometry';

/**
 * What this computer learned, drawn as what it was read out of: the console's memory map, built from
 * the runtime's own memory views. **Every line is a field on a record, never a score or a guess**: a
 * fact cites a passage of a document, the document sits in a source, a rule is the one its fact
 * governs, and a restatement names the fact it repeats. A fact that cites nothing hangs off nothing.
 */

export const MEMORY_MAP_NODE = {
  /** One fact, convention or rule, as the person's agents are told it. */
  MEMORY: 'memory',
  /** A file or page a fact cites, from `evidence.document`. */
  DOCUMENT: 'document',
  /** Where the document was read from, from `evidence.source`. */
  SOURCE: 'source',
  /** The rule a fact governs, from `item.rule`. */
  RULE: 'rule',
} as const;

export type MemoryMapNodeKind = (typeof MEMORY_MAP_NODE)[keyof typeof MEMORY_MAP_NODE];

export const MEMORY_LINK = {
  /** A fact and the document its evidence cites. */
  CITES: 'cites',
  /** A document and the source it was read from. */
  HELD_IN: 'held_in',
  /** A fact and the rule it governs. */
  GOVERNS: 'governs',
  /** A fact and the earlier fact it restates, through `duplicateOf`. */
  RESTATES: 'restates',
} as const;

export type MemoryLinkKind = (typeof MEMORY_LINK)[keyof typeof MEMORY_LINK];

export type MemoryMapNode = Placed & {
  kind: MemoryMapNodeKind;
  /** The memory item the node is, or names: a rule node carries the item it came from. */
  item?: string;
  status?: MemoryItemView['status'];
  memoryKind?: MemoryItemView['kind'];
  /** Read from a source outside the person's trust. */
  tainted?: boolean;
  /** What the node is, said under its name: the source's kind, a rule's effect, a document's source. */
  detail?: string;
};

export interface MemoryMapEdge {
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly kind: MemoryLinkKind;
  /** The cited passage changed or went away since it was read, from `evidence.stale`. */
  readonly stale?: boolean;
}

export interface MemoryMap {
  readonly nodes: MemoryMapNode[];
  readonly edges: MemoryMapEdge[];
}

/** How big each mark is, in world pixels; lines are trimmed against these. */
export const MEMORY_MAP_PX = {
  memory: { width: 188, height: 58 },
  document: { width: 164, height: 44 },
  rule: { width: 176, height: 48 },
  source: 48,
} as const;

const FULL_TURN = 2 * Math.PI;
const MIDDLE = { x: 0.5, y: 0.5 } as const;
/** One document's ring grows with what cites it, the console's orbit numbers. */
const ORBIT = { least: 0.12, per: 0.014, most: 0.26 } as const;
/** Where the hubs sit around the middle, and the loose ring outside them all. */
const HUB_RING = 0.3;
const LOOSE_RING = 0.5;
/** Every second node on a ring is pulled in, so two names never land together. */
const STAGGER = 0.86;
const EDGE_ID_SEPARATOR = '|';

export function edgeId(from: string, to: string, kind: MemoryLinkKind): string {
  return [from, to, kind].join(EDGE_ID_SEPARATOR);
}

export const memoryMapIds = {
  document: (source: string, document: string) => `doc:${source}${EDGE_ID_SEPARATOR}${document}`,
  source: (source: string) => `src:${source}`,
  rule: (item: string) => `rule:${item}`,
};

/** A document said by its last part, since the folders above it identify nothing on a map. */
export function documentLabel(document: string): string {
  const parts = document.split(/[\\/]/).filter((part) => part !== '');
  return parts[parts.length - 1] ?? document;
}

/** The source an evidence names, by name or, once it was removed, by its id. */
function sourceNamed(name: string, sources: readonly MemorySourceView[]): MemorySourceView | undefined {
  return sources.find((source) => source.name === name || source.id === name);
}

interface Gathered {
  readonly documents: Map<string, MemoryMapNode>;
  readonly sources: Map<string, MemoryMapNode>;
  readonly orbits: Map<string, MemoryMapNode[]>;
  readonly loose: MemoryMapNode[];
  readonly edges: MemoryMapEdge[];
}

/**
 * The map of the items listed, laid out as the console seeds its own: each document with the facts that
 * cite it on a ring around it, and the sources, the rules and the facts citing nothing outside them all.
 * No randomness, so the same record seeds the same picture twice.
 */
export function memoryMap(items: readonly MemoryItemView[], sources: readonly MemorySourceView[], kindLabel: (kind: MemorySourceView['kind']) => string): MemoryMap {
  const gathered: Gathered = { documents: new Map(), sources: new Map(), orbits: new Map(), loose: [], edges: [] };
  const sorted = [...items].sort((a, b) => a.id.localeCompare(b.id));
  for (const item of sorted) gather(item, sources, kindLabel, gathered);
  const listed = new Set(sorted.map((item) => item.id));
  for (const item of sorted) {
    // A restatement is drawn only where the fact it repeats is on the map too, or the line leads off it.
    if (item.duplicateOf !== undefined && listed.has(item.duplicateOf.id)) {
      gathered.edges.push({ id: edgeId(item.id, item.duplicateOf.id, MEMORY_LINK.RESTATES), from: item.id, to: item.duplicateOf.id, kind: MEMORY_LINK.RESTATES });
    }
  }
  const hubs = [...gathered.documents.values()];
  const nodes = placeAll(hubs, gathered.orbits, [...gathered.sources.values(), ...gathered.loose]);
  return { nodes: centred(nodes), edges: gathered.edges };
}

/** One item's node, its rule, and what its evidence cites, each line read off a field of the item. */
function gather(item: MemoryItemView, sources: readonly MemorySourceView[], kindLabel: (kind: MemorySourceView['kind']) => string, into: Gathered): void {
  const memory = memoryNode(item);
  let hung = false;
  for (const evidence of item.evidence) {
    const documentId = memoryMapIds.document(evidence.source, evidence.document);
    const sourceId = memoryMapIds.source(evidence.source);
    if (!into.documents.has(documentId)) {
      into.documents.set(documentId, { ...blank(documentId, documentLabel(evidence.document), MEMORY_MAP_NODE.DOCUMENT), detail: evidence.source });
      into.edges.push({ id: edgeId(documentId, sourceId, MEMORY_LINK.HELD_IN), from: documentId, to: sourceId, kind: MEMORY_LINK.HELD_IN });
    }
    if (!into.sources.has(sourceId)) {
      const known = sourceNamed(evidence.source, sources);
      into.sources.set(sourceId, { ...blank(sourceId, evidence.source, MEMORY_MAP_NODE.SOURCE), ...(known === undefined ? {} : { detail: kindLabel(known.kind) }) });
    }
    const citeId = edgeId(item.id, documentId, MEMORY_LINK.CITES);
    // Two passages of one document are one line, stale only when every passage it cites changed.
    const already = into.edges.findIndex((edge) => edge.id === citeId);
    if (already >= 0) {
      const before = into.edges[already] as MemoryMapEdge;
      into.edges[already] = { ...before, stale: before.stale === true && evidence.stale };
      continue;
    }
    into.edges.push({ id: citeId, from: item.id, to: documentId, kind: MEMORY_LINK.CITES, stale: evidence.stale });
    if (!hung) {
      into.orbits.set(documentId, [...(into.orbits.get(documentId) ?? []), memory]);
      hung = true;
    }
  }
  if (!hung) into.loose.push(memory);
  if (item.rule !== undefined) {
    const ruleId = memoryMapIds.rule(item.id);
    into.loose.push({ ...blank(ruleId, item.rule.sentence, MEMORY_MAP_NODE.RULE), item: item.id, detail: item.rule.effect });
    into.edges.push({ id: edgeId(item.id, ruleId, MEMORY_LINK.GOVERNS), from: item.id, to: ruleId, kind: MEMORY_LINK.GOVERNS });
  }
}

function memoryNode(item: MemoryItemView): MemoryMapNode {
  return {
    ...blank(item.id, item.statement, MEMORY_MAP_NODE.MEMORY),
    item: item.id,
    status: item.status,
    memoryKind: item.kind,
    tainted: item.tainted,
  };
}

/** A node before it is placed, sized for its kind. Cards write their own name; a source's hangs below it. */
function blank(id: string, label: string, kind: MemoryMapNodeKind): MemoryMapNode {
  const base = { id, label, kind, x: MIDDLE.x, y: MIDDLE.y, depth: MIDDLE.y };
  if (kind === MEMORY_MAP_NODE.SOURCE) return { ...base, width: MEMORY_MAP_PX.source };
  const box = MEMORY_MAP_PX[kind];
  return { ...base, width: box.width, height: box.height, captioned: false };
}

/** Every hub with its own ring around it, then the loose nodes outside them all. */
function placeAll(hubs: readonly MemoryMapNode[], orbits: ReadonlyMap<string, MemoryMapNode[]>, loose: readonly MemoryMapNode[]): MemoryMapNode[] {
  const placed: MemoryMapNode[] = [];
  hubs.forEach((hub, index) => {
    const centre = hubs.length === 1 ? MIDDLE : at(START + (index / hubs.length) * FULL_TURN, staggered(HUB_RING, index));
    placed.push({ ...hub, ...centre });
    const held = orbits.get(hub.id) ?? [];
    placed.push(...ringAround(held, orbitOf(held.length), centre));
  });
  placed.push(...ringAround(loose, hubs.length === 0 ? HUB_RING : LOOSE_RING));
  return placed;
}

function ringAround(members: readonly MemoryMapNode[], radius: number, centre: { x: number; y: number } = MIDDLE): MemoryMapNode[] {
  return fan(START, FULL_TURN, members.length, true).map((angle, spoke) => ({
    ...(members[spoke] as MemoryMapNode),
    ...at(angle, staggered(radius, spoke), centre),
  }));
}

function staggered(radius: number, index: number): number {
  return index % 2 === 1 ? radius * STAGGER : radius;
}

function orbitOf(memories: number): number {
  return Math.min(ORBIT.most, Math.max(ORBIT.least, ORBIT.least + memories * ORBIT.per));
}

/** What travels with a dragged document: the facts that cite it, or the cluster tears in half. */
export function carriedWith(map: MemoryMap, id: string): string[] {
  const node = map.nodes.find((each) => each.id === id);
  if (node === undefined || node.kind !== MEMORY_MAP_NODE.DOCUMENT) return [];
  return map.edges.filter((edge) => edge.to === id && edge.kind === MEMORY_LINK.CITES).map((edge) => edge.from);
}

/** The order the arrow keys walk the map in: facts first, as listed, then what they cite. */
export function walkOrder(map: MemoryMap): string[] {
  const rank: Record<MemoryMapNodeKind, number> = { memory: 0, rule: 1, document: 2, source: 3 };
  return [...map.nodes].sort((a, b) => rank[a.kind] - rank[b.kind] || a.id.localeCompare(b.id)).map((node) => node.id);
}
