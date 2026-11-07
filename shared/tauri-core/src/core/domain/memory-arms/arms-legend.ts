import type { MemoryItemView } from "@memnox/core/wire";
import type { ArmsLayer, ArmsModel } from "./arms-model";
import { LOCAL_ARMS_IDS, type LocalArmsReads } from "./arms-local";
import type { MemoryMap } from "./arms-node";

/**
 * What the brain's legend takes off and what is left drawn, the Mac's `BrainLegend` and `BrainPrepared`: each area and
 * each outer layer can be put out with its eye, and Only what needs attention keeps the facts a person is asked to look
 * at with everything one line from them. **The brain is laid out from the whole record**, so taking something off
 * never moves what stays.
 */

/** The layers the legend lists below the areas; memory is listed area by area instead. */
export const LEGEND_LAYERS = ["skill", "rule", "app"] as const;
export type LegendLayer = (typeof LEGEND_LAYERS)[number];

/** What the legend took off: areas by their key, layers, and whether only what needs attention stays. */
export type BrainCut = {
  readonly areas: ReadonlySet<string>;
  readonly layers: ReadonlySet<LegendLayer>;
  /** The record's nodes a person is asked to look at, present only while Only what needs attention is on. */
  readonly attention?: ReadonlySet<string>;
};

export const NOTHING_CUT: BrainCut = { areas: new Set(), layers: new Set() };

/** The statuses a person is asked to look at, the Mac's `MemoryGroups.attentionStatuses`. */
const ATTENTION: ReadonlySet<MemoryItemView["status"]> = new Set(["candidate", "conflicting", "outdated"]);

/** The nodes that need attention: every fact waiting, in conflict or out of date, and every candidate the workspace holds. */
export function attentionNodes(reads: LocalArmsReads): Set<string> {
  const ids = new Set<string>();
  for (const item of reads.items ?? []) if (ATTENTION.has(item.status)) ids.add(LOCAL_ARMS_IDS.fact(item.id));
  for (const node of reads.workspace?.nodes ?? []) {
    if (node.kind === "candidate" || node.status === "candidate") ids.add(LOCAL_ARMS_IDS.workspace(node.id));
  }
  return ids;
}

/** The legend's rows: each area with its colour and count in the order the brain packs them, and each outer layer with its count. */
export function legendRows(model: ArmsModel): {
  areas: { key: string; label: string; count: number; ink: string }[];
  layers: { layer: LegendLayer; count: number }[];
} {
  const areas = model.sectors.map((sector) => ({ key: sector.key, label: sector.label, count: sector.count, ink: sector.ink }));
  const counted = (layer: ArmsLayer) => model.items.filter((item) => item.layer === layer).length;
  const layers = LEGEND_LAYERS.map((layer) => ({ layer, count: counted(layer) })).filter((row) => row.count > 0);
  return { areas, layers };
}

/**
 * The model as drawn once the legend has taken its share off. Under attention a fact stays with everything one line
 * from it on the record, and the layers the record draws no line to go, as on the Mac.
 */
export function drawnModel(model: ArmsModel, map: MemoryMap, cut: BrainCut): ArmsModel {
  if (cut.areas.size === 0 && cut.layers.size === 0 && cut.attention === undefined) return model;
  const kept = cut.attention === undefined ? undefined : withNeighbours(cut.attention, map);
  const items = model.items.filter((item) => {
    if (item.layer !== "memory") return !cut.layers.has(item.layer) && kept === undefined;
    if (item.sector !== undefined && cut.areas.has(item.sector)) return false;
    if (kept === undefined) return true;
    return item.nodeId !== undefined && kept.has(item.nodeId);
  });
  const held = new Set(items.map((item) => item.sector));
  const sectors = model.sectors.filter((sector) => !cut.areas.has(sector.key) && (kept === undefined || held.has(sector.key)));
  return { ...model, items, sectors, empty: items.length === 0 };
}

function withNeighbours(asked: ReadonlySet<string>, map: MemoryMap): Set<string> {
  const kept = new Set(asked);
  for (const edge of map.edges) {
    if (asked.has(edge.from)) kept.add(edge.to);
    if (asked.has(edge.to)) kept.add(edge.from);
  }
  return kept;
}

/**
 * The heading's counts off what is drawn, as the Mac's `MemoryGroups.stats` counts its drawn map: the facts, the sources
 * memory was read through with the apps and servers round the outside, and every line between two drawn marks.
 */
export function drawnStats(
  drawn: ArmsModel,
  map: MemoryMap,
  sourceAreas: readonly (string | undefined)[],
  cut: BrainCut,
): { memories: number; sources: number; connections: number } {
  const nodes = new Set(drawn.items.flatMap((item) => (item.nodeId === undefined ? [] : [item.nodeId])));
  const memories = map.nodes.filter((node) => node.kind === "memory" && nodes.has(node.id)).length;
  // A source is the hub of its area, two lines from any fact, so attention keeps none, as on the Mac.
  const read = cut.attention !== undefined ? 0 : sourceAreas.filter((area) => area === undefined || !cut.areas.has(area)).length;
  const tiles = drawn.items.filter((item) => item.layer === "app").length;
  const connections = map.edges.filter((edge) => nodes.has(edge.from) && nodes.has(edge.to)).length;
  return { memories, sources: read + tiles, connections };
}
