import { systemName, type MemoryMapNode } from "./arms-node";

import { isFace, sourceLogo } from "./arms-faces";
import { SALT, stableUnit } from "./arms-hash";
import { sectorInk } from "./arms-ink";
import { CLUSTER, clusterRadius, packDiscs, sunflower, type Disc, type Vec2 } from "./arms-pack";
import { LAYER_AT, OUTLINE_AREA, OUTLINE_LENGTH, arcShareOf, arcSpaced, layerOfPoint, thetaAtArcShare } from "./arms-shape";

/**
 * What the ARMS map holds, read off the record and nothing else, and built
 * from it: AGENTS.md (or the CLAUDE.md the record holds) at the centre with
 * the skills it hands out, each area of memory a packed cluster round a hub
 * of its own, the rules in force on a gold ring that wraps only what exists,
 * and the connected systems outside it. An empty record is an empty model,
 * so nothing is drawn for nothing.
 */

export const ARMS_LAYERS = ["skill", "memory", "rule", "app"] as const;
export type ArmsLayer = (typeof ARMS_LAYERS)[number];

export type ArmsItem = {
  id: string;
  layer: ArmsLayer;
  label: string;
  /** Where round the outline it sits, and how far out as a share of it. */
  theta: number;
  f: number;
  /** How far round the long axis it is turned in depth. */
  phi: number;
  /** The area it sits in, for memory; the area it feeds, for an app. */
  sector?: string;
  /** The hub it grows out of and hangs off: an area's hub, or the centre for a skill and a hub. */
  parent?: string;
  /** Epoch milliseconds, where the record dates it. */
  time?: number;
  /** The map node it is, so the existing card opens on it. */
  nodeId?: string;
  /** A hub: the centre, or the labelled middle of one area. */
  hub?: boolean;
  /** The centre itself, where agents read what they are handed. */
  core?: boolean;
  /** How many things an area's hub holds. */
  holds?: number;
  /** What the map node is, so somebody is drawn as a face and a source as its mark. */
  kind?: MemoryMapNode["kind"];
  /** The system it came from, where the record says. */
  system?: string;
  /** A system's slug, for an app tile's mark. */
  slug?: string;
  /** The brand mark drawn inside it: an app's, a source hub's or a source's. */
  logo?: string;
  /** Somebody's own picture, where the workspace holds one. */
  picture?: string;
  /** An app's number round the ring, from 1 at the top going clockwise. */
  number?: number;
  /** When an app last delivered something the record dates, if it ever did. */
  lastUsed?: number;
  /** A rule's effect, where the rule names one. */
  effect?: string;
  /** Searchable words beyond the label. */
  words: string;
};

/** One area of memory: its cluster's disc in brain units and the hub at its middle. */
export type ArmsSector = {
  key: string;
  label: string;
  count: number;
  ink: string;
  x: number;
  y: number;
  r: number;
  /** The angle its middle sits at round the outline, which an app it came from sits outside. */
  theta: number;
  hubId: string;
};

/** How far out the outline that wraps the clusters sits, and the two rings outside it, as shares of the outline. */
export type ArmsRings = { envelope: number; rules: number; apps: number };

export type ArmsInput = {
  nodes: readonly MemoryMapNode[];
  /** The record's own lines, which say what a MEMORY.md lists. */
  edges?: readonly { from: string; to: string }[];
  skills: readonly { name: string; description?: string; version?: string }[];
  rules: readonly { name: string; effect?: string }[];
  apps: readonly { slug: string; name: string; logo?: string }[];
  /** When the record dates a map node, if it does. */
  timeOf: (nodeId: string) => number | undefined;
  /** Somebody's own picture by their map node, where the workspace holds one. */
  pictureOf?: (nodeId: string) => string | undefined;
};

export type ArmsModel = {
  items: ArmsItem[];
  sectors: ArmsSector[];
  memories: number;
  rings: ArmsRings;
  /** The centre's disc, where the skills sit, if anything stands there. */
  core?: Disc;
  empty: boolean;
};

export const AGENTS_HUB_ID = "skill:AGENTS.md";
/** The area a MEMORY.md and the memories it lists make together. */
export const MEMORY_INDEX = "memory-index";
const HUB_PREFIX = "hub:";
const TAU = Math.PI * 2;
/** Memory is packed inside this share of the outline, which leaves the rules ring room outside it. */
const MEMORY_OUTER = 0.82;
/** The centre's least radius in brain units, and how much of a skill cluster's size it takes. */
const CORE_LEAST = 0.12;
const CORE_SHARE = 0.85;
/** The skills keep clear of this share of the centre, so AGENTS.md stands alone in the middle. */
const CORE_INNER = 0.45;
/** The outline wraps the furthest cluster with this much to spare, and the rings stand this far outside it. */
const ENVELOPE_PAD = 0.05;
const RULES_OUT = 0.09;
const APPS_OUT = 0.24;
/** The least distance between two app tiles round the outside, in brain units. */
const APP_SPACING = 0.36;
const RELAX_PASSES = 24;
/** How far a piece turns in depth either side of its cluster, so a cluster stays one in the 3D view. */
const CLUSTER_DEPTH = 0.5;
/** The outline's width over its height, which the packing spiral follows. */
const STRETCH = 1.22 / 0.86;
const DAY = 86_400_000;
const AGE_MOST_DAYS = 30;

const CORE_DOC = /(^|[\\/])(agents|claude)\.md$/i;
const INDEX_DOC = /(^|[\\/])memory\.md$/i;

/** Kinds of thing that are memory, whichever system brought them. */
const UPLOADED = "uploaded";
const SECTOR_OF_KIND: Partial<Record<MemoryMapNode["kind"], string>> = {
  memory: "settled",
  person: "people",
  group: "people",
};
const SECTOR_LABEL: Record<string, string> = {
  settled: "Settled",
  people: "People",
  files: "Files",
  other: "Other",
  [MEMORY_INDEX]: "MEMORY.md",
};

const EMPTY: ArmsModel = {
  items: [],
  sectors: [],
  memories: 0,
  rings: { envelope: LAYER_AT.core, rules: LAYER_AT.core + RULES_OUT, apps: LAYER_AT.core + RULES_OUT + APPS_OUT },
  empty: true,
};

/** The area a memory node is drawn in: the system it came from, else what it is. */
export function sectorKeyOf(node: MemoryMapNode): string {
  if (node.system !== undefined && node.system !== "") return node.system;
  if (node.origin === UPLOADED) return "files";
  return SECTOR_OF_KIND[node.kind] ?? "other";
}

export function sectorLabel(key: string): string {
  return SECTOR_LABEL[key] ?? systemName(key);
}

/** Slack and mail hand text over with HTML entities in it, which a label reads as the characters they stand for. */
/** The highest code point there is; a number past it is left as written. */
const MOST_CODE_POINT = 0x10ffff;
const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
export function plainText(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (whole, name: string) => {
    const code = name.startsWith("#x") || name.startsWith("#X") ? Number.parseInt(name.slice(2), 16) : name.startsWith("#") ? Number.parseInt(name.slice(1), 10) : undefined;
    if (code === undefined) return ENTITIES[name.toLowerCase()] ?? whole;
    return code > 0 && code <= MOST_CODE_POINT ? String.fromCodePoint(code) : whole;
  });
}

function baseName(label: string): string {
  return label.split(/[\\/]/).pop() ?? label;
}

const inMemory = (point: Vec2) => layerOfPoint(point).f <= MEMORY_OUTER;

/**
 * Each area as a cluster, largest first, its disc sized by the square root of
 * what it holds and packed round the centre so no two lie over each other.
 */
export function sectorsOf(counts: ReadonlyMap<string, number>, core?: Disc): ArmsSector[] {
  const ordered = [...counts.entries()].sort(([a, left], [b, right]) => right - left || a.localeCompare(b));
  const taken = core === undefined ? [] : [core];
  const room = OUTLINE_AREA * MEMORY_OUTER ** 2 - taken.reduce((sum, disc) => sum + Math.PI * disc.r ** 2, 0);
  const { discs } = packDiscs(
    ordered.map(([, count]) => clusterRadius(count)),
    { contains: inMemory, area: room, middle: { x: 0, y: 0 }, stretch: STRETCH, taken },
  );
  return ordered.map(([key, count], index) => {
    const disc = discs[index]!;
    return {
      key,
      label: sectorLabel(key),
      count,
      ink: sectorInk(index),
      x: disc.x,
      y: disc.y,
      r: disc.r,
      theta: layerOfPoint(disc).theta,
      hubId: `${HUB_PREFIX}${key}`,
    };
  });
}

/** Spreads values round a circle of `period` that crowd each other, so no two tiles overlap round the outside. */
export function spread(values: number[], least: number, period: number = TAU): number[] {
  const out = [...values];
  const gapOf = (from: number, to: number) => ((((to - from) % period) + period * 1.5) % period) - period / 2;
  for (let pass = 0; pass < RELAX_PASSES; pass += 1) {
    for (let a = 0; a < out.length; a += 1) {
      for (let b = a + 1; b < out.length; b += 1) {
        const gap = gapOf(out[a]!, out[b]!);
        if (Math.abs(gap) >= least) continue;
        const push = (least - Math.abs(gap)) / 2;
        const sign = gap >= 0 ? 1 : -1;
        out[a] = out[a]! - push * sign;
        out[b] = out[b]! + push * sign;
      }
    }
  }
  return out;
}

/** How long ago an app last delivered, as the chip under its tile says it: "1D" up to "30D+". */
export function ageChip(time: number, now: number): string {
  const days = Math.max(1, Math.ceil((now - time) / DAY));
  return days >= AGE_MOST_DAYS ? `${AGE_MOST_DAYS}D+` : `${days}D`;
}

/** The furthest share of the outline any point of these discs reaches. */
function reachOf(discs: readonly Disc[]): number {
  let most = 0;
  for (const disc of discs) {
    for (let at = 0; at < CLUSTER.rimSamples; at += 1) {
      const angle = (at / CLUSTER.rimSamples) * TAU;
      most = Math.max(most, layerOfPoint({ x: disc.x + Math.cos(angle) * disc.r, y: disc.y + Math.sin(angle) * disc.r }).f);
    }
  }
  return most;
}

export function armsModel(input: ArmsInput): ArmsModel {
  const documents = input.nodes.filter((node) => node.kind === "document").sort((a, b) => a.id.localeCompare(b.id));
  const coreDoc = documents.find((node) => CORE_DOC.test(node.label));
  const indexDoc = documents.find((node) => INDEX_DOC.test(node.label));
  const memoryNodes = input.nodes.filter((node) => node.kind !== "policy" && node.id !== coreDoc?.id);
  const rules = rulesOf(input);
  const nothing = memoryNodes.length === 0 && input.skills.length === 0 && rules.length === 0 && input.apps.length === 0;
  if (nothing && coreDoc === undefined) return EMPTY;

  /* What a MEMORY.md lists is what the record joins it to, so they are drawn as one cluster round it. */
  const listed = new Set<string>();
  if (indexDoc !== undefined) {
    for (const edge of input.edges ?? []) {
      if (edge.from === indexDoc.id) listed.add(edge.to);
      if (edge.to === indexDoc.id) listed.add(edge.from);
    }
  }
  const areaOf = (node: MemoryMapNode) => (listed.has(node.id) ? MEMORY_INDEX : sectorKeyOf(node));
  const members = new Map<string, MemoryMapNode[]>();
  for (const node of memoryNodes) {
    if (node.id === indexDoc?.id) continue;
    const key = areaOf(node);
    const list = members.get(key);
    if (list === undefined) members.set(key, [node]);
    else list.push(node);
  }
  if (indexDoc !== undefined && !members.has(MEMORY_INDEX)) members.set(MEMORY_INDEX, []);

  const hasCore = input.skills.length > 0 || members.size > 0 || coreDoc !== undefined;
  const core: Disc | undefined = hasCore ? { x: 0, y: 0, r: Math.max(CORE_LEAST, clusterRadius(input.skills.length) * CORE_SHARE) } : undefined;
  const counts = new Map([...members.entries()].map(([key, list]) => [key, list.length]));
  const sectors = sectorsOf(counts, core);
  const envelope = Math.max(LAYER_AT.core, reachOf([...(core === undefined ? [] : [core]), ...sectors]) + ENVELOPE_PAD);
  const rings: ArmsRings = { envelope, rules: envelope + RULES_OUT, apps: envelope + RULES_OUT + APPS_OUT };
  const items: ArmsItem[] = [];

  if (core !== undefined) {
    items.push({
      id: AGENTS_HUB_ID,
      layer: "skill",
      label: coreDoc === undefined ? "AGENTS.md" : baseName(coreDoc.label),
      theta: 0,
      f: 0,
      phi: 0,
      hub: true,
      core: true,
      holds: input.skills.length,
      ...(coreDoc === undefined ? {} : { nodeId: coreDoc.id }),
      words: `skills instructions AGENTS.md CLAUDE.md ${coreDoc?.detail ?? ""}`,
    });
    const spots = sunflower(input.skills.map((skill) => skill.name), core, "core", CORE_INNER);
    for (const skill of input.skills) {
      items.push({
        id: `skill:${skill.name}`,
        layer: "skill",
        label: skill.name,
        ...layerOfPoint(spots.get(skill.name)!),
        phi: stableUnit(skill.name, SALT.latitude) * Math.PI,
        parent: AGENTS_HUB_ID,
        words: skill.description ?? "",
      });
    }
  }

  for (const sector of sectors) {
    const depth = stableUnit(sector.key, SALT.latitude) * Math.PI;
    const index = sector.key === MEMORY_INDEX ? indexDoc : undefined;
    if (index !== undefined) sector.hubId = `memory:${index.id}`;
    const hubLogo = sourceLogo(sector.key) ?? input.apps.find((app) => app.slug === sector.key)?.logo;
    items.push({
      id: sector.hubId,
      layer: "memory",
      label: index === undefined ? sector.label : baseName(index.label),
      ...layerOfPoint(sector),
      phi: depth,
      sector: sector.key,
      parent: AGENTS_HUB_ID,
      hub: true,
      holds: sector.count,
      ...(hubLogo === undefined ? {} : { logo: hubLogo }),
      ...(index === undefined ? {} : { nodeId: index.id }),
      words: `${sector.label} ${index?.detail ?? ""}`,
    });
    const list = members.get(sector.key) ?? [];
    const spots = sunflower(list.map((node) => node.id), sector, sector.key);
    for (const node of list) {
      const time = input.timeOf(node.id);
      const face = isFace(node);
      const picture = face ? input.pictureOf?.(node.id) : undefined;
      const logo = !face && node.kind === "document" ? sourceLogo(node.system) : undefined;
      items.push({
        id: `memory:${node.id}`,
        layer: "memory",
        label: plainText(node.label),
        ...layerOfPoint(spots.get(node.id)!),
        phi: depth + (stableUnit(node.id, SALT.latitude) - 0.5) * CLUSTER_DEPTH,
        sector: sector.key,
        parent: sector.hubId,
        nodeId: node.id,
        kind: node.kind,
        ...(node.system === undefined ? {} : { system: node.system }),
        ...(picture === undefined ? {} : { picture }),
        ...(logo === undefined ? {} : { logo }),
        ...(time === undefined ? {} : { time }),
        words: `${node.statement ?? ""} ${node.detail ?? ""} ${node.href ?? ""} ${sector.label}`,
      });
    }
  }

  const ruleAngles = arcSpaced(rules.length, Math.PI / 2);
  rules.forEach((rule, index) => {
    items.push({
      id: `rule:${rule.name}`,
      layer: "rule",
      label: rule.name,
      theta: ruleAngles[index] ?? 0,
      f: rings.rules,
      /* On the ring itself in depth too, which is drawn on the outline's own plane. */
      phi: 0,
      ...(rule.effect === undefined ? {} : { effect: rule.effect }),
      ...(rule.nodeId === undefined ? {} : { nodeId: rule.nodeId }),
      words: rule.effect ?? "",
    });
  });

  items.push(...appItems(input, sectors, rings));
  return {
    items,
    sectors,
    memories: memoryNodes.filter((node) => node.kind === "memory").length,
    rings,
    ...(core === undefined ? {} : { core }),
    empty: false,
  };
}

/** The rules in force, by name, with any the map itself drew as a policy node. */
function rulesOf(input: ArmsInput): { name: string; effect?: string; nodeId?: string }[] {
  const named = new Map<string, { name: string; effect?: string; nodeId?: string }>();
  for (const rule of input.rules) named.set(rule.name, { ...rule });
  for (const node of input.nodes) {
    if (node.kind !== "policy") continue;
    const was = named.get(node.label);
    named.set(node.label, { ...(was ?? { name: node.label }), nodeId: node.id });
  }
  return [...named.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Each connected system outside the area it fed, spread by distance round
 * the ring so no two tiles touch, numbered from the top going clockwise, and
 * dated by the newest thing it delivered where the record dates one.
 */
function appItems(input: ArmsInput, sectors: readonly ArmsSector[], rings: ArmsRings): ArmsItem[] {
  const bySector = new Map(sectors.map((sector) => [sector.key, sector]));
  const ordered = [...input.apps].sort((a, b) => a.slug.localeCompare(b.slug));
  const loose = ordered.filter((app) => !bySector.has(app.slug));
  const wanted = ordered.map((app) => {
    const sector = bySector.get(app.slug);
    if (sector !== undefined) return arcShareOf(sector.theta);
    return arcShareOf(-Math.PI / 2 + ((loose.indexOf(app) + 0.5) / Math.max(1, loose.length)) * Math.PI);
  });
  const least = Math.min(APP_SPACING / (OUTLINE_LENGTH * rings.apps), 1 / Math.max(1, ordered.length));
  const angles = spread(wanted, least, 1).map(thetaAtArcShare);
  const clockwise = (theta: number) => (((Math.PI / 2 - theta) % TAU) + TAU) % TAU;
  const rank = new Map(
    ordered
      .map((app, index) => ({ slug: app.slug, turn: clockwise(angles[index] ?? 0) }))
      .sort((a, b) => a.turn - b.turn || a.slug.localeCompare(b.slug))
      .map((each, index) => [each.slug, index + 1] as const),
  );
  const newest = new Map<string, number>();
  for (const node of input.nodes) {
    if (node.system === undefined) continue;
    const time = input.timeOf(node.id);
    if (time !== undefined) newest.set(node.system, Math.max(time, newest.get(node.system) ?? time));
  }
  return ordered.map((app, index) => {
    const lastUsed = newest.get(app.slug);
    const logo = sourceLogo(app.slug) ?? app.logo;
    return {
      id: `app:${app.slug}`,
      layer: "app",
      label: app.name,
      theta: angles[index] ?? 0,
      f: rings.apps,
      phi: stableUnit(app.slug, SALT.latitude) * Math.PI,
      slug: app.slug,
      number: rank.get(app.slug) ?? index + 1,
      ...(lastUsed === undefined ? {} : { lastUsed }),
      ...(logo === undefined ? {} : { logo }),
      ...(bySector.has(app.slug) ? { sector: app.slug } : {}),
      words: app.slug,
    };
  });
}

/** The items a search matches, by label, words or path, ignoring case. */
export function matching(items: readonly ArmsItem[], query: string): Set<string> {
  const asked = query.trim().toLowerCase();
  if (asked === "") return new Set();
  return new Set(
    items
      .filter((item) => `${item.label} ${item.words}`.toLowerCase().includes(asked))
      .map((item) => item.id),
  );
}

/** The match Enter opens: a piece before a hub, since a hub is only its area's name. */
export function firstMatch(items: readonly ArmsItem[], matches: ReadonlySet<string>): ArmsItem | undefined {
  return items.find((item) => matches.has(item.id) && item.hub !== true) ?? items.find((item) => matches.has(item.id));
}
