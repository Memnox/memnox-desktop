import { describe, expect, it } from "vitest";

import type { MemoryMapNode } from "../src/core/domain/memory-arms/arms-node";

import { faceInk, initialsFor, profileOf, sourceLogo } from "../src/core/domain/memory-arms/arms-faces";

const node = (id: string, kind: MemoryMapNode["kind"], extra: Partial<MemoryMapNode> = {}): MemoryMapNode => ({
  id,
  kind,
  label: id,
  ...extra,
});

describe("the brain's faces", () => {
  it("finds a source's shipped mark, agents included, and nothing it would have to guess", () => {
    expect(sourceLogo("slack")).toBe("tool:slack");
    expect(sourceLogo("notion")).toBe("tool:notion");
    expect(sourceLogo("claude_code")).toBe("agent:claude");
    expect(sourceLogo("codex")).toBe("agent:openai");
    expect(sourceLogo("settled")).toBeUndefined();
    expect(sourceLogo(undefined)).toBeUndefined();
  });

  it("letters somebody by their initials, on a colour their name always draws", () => {
    expect(initialsFor("Ada Lovelace")).toBe("AL");
    expect(initialsFor("")).toBe("@");
    expect(faceInk("Ada Lovelace")).toBe(faceInk(" ada lovelace "));
  });

  it("lists what the record joins somebody to, grouped by how, with the sources it came from", () => {
    const nodes = [
      node("person:ada", "person", { system: "slack" }),
      node("m1", "memory", { system: "github" }),
      node("m2", "memory"),
      node("d1", "document", { system: "notion" }),
    ];
    const edges = [
      { id: "e1", from: "person:ada", to: "m1", kind: "said" as const },
      { id: "e2", from: "m2", to: "person:ada", kind: "approved" as const },
      { id: "e3", from: "d1", to: "person:ada", kind: "mentions" as const },
      { id: "e4", from: "m1", to: "m2", kind: "updates" as const },
    ];
    const profile = profileOf("person:ada", nodes, edges);
    expect(profile.groups.map((group) => group.label)).toEqual(["Said", "Approved", "Named in"]);
    expect(profile.sources).toEqual(["github", "notion", "slack"]);
  });
});
