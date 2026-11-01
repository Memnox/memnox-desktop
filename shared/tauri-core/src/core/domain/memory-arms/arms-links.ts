import type { MemoryMapEdge } from "./arms-node";

import { AGENTS_HUB_ID, type ArmsModel } from "./arms-model";

/** The most lines a hovered app draws to what it delivered, so a big source is a fan rather than a blot. */
const APP_FAN = 48;

/**
 * What lights when a mark is hovered: the memory map's own stated lines
 * between the things on it, each skill to the centre, each area's hub to the
 * centre and to what it holds, and an app to what it delivered. Nothing is
 * joined that the record or the grouping does not join.
 */
export function linksOf(model: ArmsModel, edges: readonly MemoryMapEdge[]): Map<string, string[]> {
  const byNode = new Map<string, string>();
  for (const item of model.items) if (item.nodeId !== undefined) byNode.set(item.nodeId, item.id);
  const links = new Map<string, string[]>();
  const join = (a: string, b: string) => {
    if (a === b) return;
    links.set(a, [...(links.get(a) ?? []), b]);
    links.set(b, [...(links.get(b) ?? []), a]);
  };
  for (const edge of edges) {
    const from = byNode.get(edge.from);
    const to = byNode.get(edge.to);
    if (from !== undefined && to !== undefined) join(from, to);
  }
  for (const item of model.items) {
    if (item.layer === "skill" && item.hub !== true) join(AGENTS_HUB_ID, item.id);
    /* An area's hub to the centre, which is the spoke the brain already draws. */
    if (item.hub === true && item.core !== true && item.parent !== undefined) join(item.parent, item.id);
  }
  /* A hub to what it holds, as a fan so a big area lights a spread rather than a blot. */
  for (const hub of model.items) {
    if (hub.hub !== true || hub.core === true) continue;
    const held = model.items.filter((item) => item.parent === hub.id);
    links.set(hub.id, [...(links.get(hub.id) ?? []), ...held.slice(0, APP_FAN).map((item) => item.id)]);
    for (const item of held) links.set(item.id, [...(links.get(item.id) ?? []), hub.id]);
  }
  for (const app of model.items) {
    if (app.layer !== "app" || app.sector === undefined) continue;
    const fed = model.items.filter((item) => item.layer === "memory" && item.sector === app.sector).slice(0, APP_FAN);
    links.set(app.id, [...(links.get(app.id) ?? []), ...fed.map((item) => item.id)]);
  }
  return links;
}
