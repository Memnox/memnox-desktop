import { describe, expect, it } from "vitest";

import type { MemoryMapNode } from "../src/core/domain/memory-arms/arms-node";

import { timelineFrame } from "../src/core/domain/memory-arms/arms-lanes";
import { AGENTS_HUB_ID, MEMORY_INDEX, ageChip, armsModel, firstMatch, matching, plainText, sectorKeyOf, sectorsOf, spread } from "../src/core/domain/memory-arms/arms-model";
import { brainPoint } from "../src/core/domain/memory-arms/arms-shape";

const node = (id: string, kind: MemoryMapNode["kind"], extra: Partial<MemoryMapNode> = {}): MemoryMapNode => ({
  id,
  kind,
  label: id,
  ...extra,
});

const input = {
  nodes: [
    node("f1", "memory", { system: "slack", statement: "Deploys freeze on Fridays" }),
    node("f2", "memory"),
    node("d1", "document", { system: "slack" }),
    node("p1", "person"),
    node("rule-node", "policy", { label: "no-prod-writes" }),
  ],
  skills: [{ name: "review" }, { name: "release" }],
  rules: [{ name: "no-prod-writes", effect: "deny" }, { name: "ask-before-deploy", effect: "ask" }],
  apps: [{ slug: "slack", name: "Slack" }, { slug: "github", name: "GitHub" }],
  timeOf: (id: string) => (id === "f1" ? 1_000 : id === "f2" ? 5_000 : undefined),
};

describe("the ARMS model", () => {
  it("puts each thing in its layer, the rules once each, and AGENTS.md at the centre", () => {
    const model = armsModel(input);
    const pieces = (name: string) => model.items.filter((item) => item.layer === name && item.hub !== true).length;
    expect(pieces("skill")).toBe(2);
    expect(pieces("memory")).toBe(4);
    expect(pieces("rule")).toBe(2);
    expect(pieces("app")).toBe(2);
    expect(model.items.find((item) => item.id === AGENTS_HUB_ID)?.f).toBe(0);
    expect(model.memories).toBe(2);
  });

  it("gives each area a labelled hub at the middle of its cluster, hung off the centre", () => {
    const model = armsModel(input);
    for (const sector of model.sectors) {
      const hub = model.items.find((item) => item.id === sector.hubId)!;
      expect(hub.hub).toBe(true);
      expect(hub.parent).toBe(AGENTS_HUB_ID);
      expect(hub.holds).toBe(sector.count);
      const at = brainPoint(hub.theta, hub.f);
      expect(at.x).toBeCloseTo(sector.x, 4);
      expect(at.y).toBeCloseTo(sector.y, 4);
    }
  });

  it("keeps every piece inside its own cluster's disc", () => {
    const model = armsModel(input);
    for (const item of model.items.filter((each) => each.layer === "memory" && each.hub !== true)) {
      const sector = model.sectors.find((each) => each.key === item.sector)!;
      const at = brainPoint(item.theta, item.f);
      expect(Math.hypot(at.x - sector.x, at.y - sector.y)).toBeLessThanOrEqual(sector.r + 1e-6);
    }
  });

  it("is empty for an empty record, with no hub drawn for nothing", () => {
    const model = armsModel({ nodes: [], skills: [], rules: [], apps: [], timeOf: () => undefined });
    expect(model.empty).toBe(true);
    expect(model.items).toEqual([]);
  });

  it("wraps a small brain nearer in than a full one", () => {
    const small = armsModel({ ...input, nodes: input.nodes.slice(0, 1) });
    const many = Array.from({ length: 300 }, (_, at) => node(`m${at}`, "memory", { system: `s${at % 6}` }));
    const full = armsModel({ ...input, nodes: many });
    expect(small.rings.envelope).toBeLessThan(full.rings.envelope);
    expect(full.rings.rules).toBeGreaterThan(full.rings.envelope);
    expect(full.rings.apps).toBeGreaterThan(full.rings.rules);
  });

  it("makes a MEMORY.md the hub of the memories it lists, and a CLAUDE.md the centre", () => {
    const nodes = [
      node("idx", "document", { label: "repo/MEMORY.md" }),
      node("claude", "document", { label: "CLAUDE.md" }),
      node("m1", "memory"),
      node("m2", "memory"),
    ];
    const model = armsModel({ ...input, nodes, edges: [{ from: "idx", to: "m1" }] });
    const hub = model.items.find((item) => item.id === "memory:idx")!;
    expect(hub.hub).toBe(true);
    expect(hub.label).toBe("MEMORY.md");
    expect(model.items.find((item) => item.id === "memory:m1")?.sector).toBe(MEMORY_INDEX);
    expect(model.items.find((item) => item.id === "memory:m2")?.sector).toBe("settled");
    const core = model.items.find((item) => item.id === AGENTS_HUB_ID)!;
    expect(core.label).toBe("CLAUDE.md");
    expect(core.nodeId).toBe("claude");
  });

  it("numbers the outer ring from 1 and dates a tile only by what it delivered", () => {
    const model = armsModel(input);
    const tiles = model.items.filter((item) => item.layer === "app");
    expect(tiles.map((tile) => tile.number).sort()).toEqual([1, 2]);
    expect(tiles.find((tile) => tile.slug === "slack")?.lastUsed).toBe(1_000);
    expect(tiles.find((tile) => tile.slug === "github")?.lastUsed).toBeUndefined();
  });

  it("says an app's age in days, capped at thirty", () => {
    const day = 86_400_000;
    expect(ageChip(0, day / 2)).toBe("1D");
    expect(ageChip(0, day * 3)).toBe("3D");
    expect(ageChip(0, day * 45)).toBe("30D+");
  });

  it("sectors memory by the system it came from, else by what it is", () => {
    expect(sectorKeyOf(node("a", "memory", { system: "github" }))).toBe("github");
    expect(sectorKeyOf(node("a", "memory"))).toBe("settled");
    expect(sectorKeyOf(node("a", "person"))).toBe("people");
    expect(sectorKeyOf(node("a", "document", { origin: "uploaded" }))).toBe("files");
  });

  it("gives the bigger area the bigger cluster, and no two lie over each other", () => {
    const sectors = sectorsOf(new Map([["slack", 90], ["people", 4], ["github", 30], ["files", 12]]), { x: 0, y: 0, r: 0.15 });
    expect(sectors[0]!.r).toBeGreaterThan(sectors[1]!.r);
    for (const a of sectors) {
      expect(Math.hypot(a.x, a.y)).toBeGreaterThanOrEqual(a.r + 0.15);
      for (const b of sectors) if (a !== b) expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeGreaterThanOrEqual(a.r + b.r);
    }
  });

  it("places the same record the same way every time", () => {
    expect(armsModel(input).items).toEqual(armsModel(input).items);
  });

  it("puts an app tile outside the area it delivered", () => {
    const model = armsModel(input);
    const slack = model.sectors.find((sector) => sector.key === "slack")!;
    const tile = model.items.find((item) => item.id === "app:slack")!;
    const gap = Math.abs(Math.atan2(Math.sin(tile.theta - slack.theta), Math.cos(tile.theta - slack.theta)));
    expect(gap).toBeLessThan(0.6);
  });

  it("spreads tiles that crowd one another", () => {
    const [a, b] = spread([1, 1.01], 0.3);
    expect(Math.abs(b! - a!)).toBeGreaterThanOrEqual(0.29);
  });

  it("finds by the words a memory says as well as its name, and opens a piece before a hub", () => {
    const items = armsModel(input).items;
    expect([...matching(items, "freeze")]).toEqual(["memory:f1"]);
    expect(matching(items, " ").size).toBe(0);
    const slack = matching(items, "slack");
    expect(slack.has("hub:slack")).toBe(true);
    expect(firstMatch(items, slack)?.hub).not.toBe(true);
  });

  it("lays dated things along time and gives the undated a row of their own per layer", () => {
    const model = armsModel(input);
    const frame = timelineFrame(model.items, model.sectors);
    const at = (id: string) => frame.places.get(id)!;
    expect(at("memory:f1").x).toBeLessThan(at("memory:f2").x);
    expect(at("memory:p1").y).not.toBeCloseTo(at("memory:f1").y, 2);
    expect(frame.first).toBe(1_000);
    expect(frame.last).toBe(5_000);
    const rules = model.items.filter((item) => item.layer === "rule").map((item) => at(item.id));
    expect(rules[0]!.x).not.toBeCloseTo(rules[1]!.x, 2);
    expect(frame.undated.map((row) => row.layer)).toContain("rule");
  });
});

describe("plainText", () => {
  it("reads HTML entities as the characters they stand for", () => {
    expect(plainText("Moise &lt;moise@memnox.com&gt; &amp; team &#39;ok&#x27;")).toBe("Moise <moise@memnox.com> & team 'ok'");
  });

  it("leaves an unknown or impossible entity as written", () => {
    expect(plainText("&bogus; &#1114112;")).toBe("&bogus; &#1114112;");
  });
});
