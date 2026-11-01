import { hashOf } from "./arms-node";
import type { MemoryMapEdge, MemoryMapNode } from "./arms-node";

/**
 * The faces the brain wears: a source's brand mark where one ships with this app, and a person's initials on a
 * colour drawn from their name. Pure, so the same name is the same colour on every load and a test can read every
 * rule. A mark is named here as `agent:claude` or `tool:slack` and turned into a file by the window, since the core
 * holds no assets.
 */

/** The agents and tools a record names as a source, by the mark the app ships for each. */
const MARKS: Readonly<Record<string, string>> = {
  claude: "agent:claude",
  claude_code: "agent:claude",
  "claude-code": "agent:claude",
  cursor: "agent:cursor",
  codex: "agent:openai",
  openai: "agent:openai",
  copilot: "agent:copilot",
  opencode: "agent:opencode",
  cline: "agent:cline",
  hermes: "agent:hermes",
  openclaw: "agent:openclaw",
  antigravity: "agent:antigravity",
  slack: "tool:slack",
  github: "tool:github",
  linear: "tool:linear",
  gmail: "tool:gmail",
  googledocs: "tool:googledocs",
  notion: "tool:notion",
};

/**
 * The mark for a source, bundled marks only: a guessed remote address is a placeholder where a logo should be, so
 * anything else falls back to the glyph.
 */
export function sourceLogo(system: string | undefined): string | undefined {
  if (system === undefined || system === "") return undefined;
  const name = system.toLowerCase();
  return MARKS[name] ?? MARKS[name.split("_")[0] ?? name];
}

/** The colours a face is drawn in, the theme's own chart hues, so it follows light and dark. */
/** The brain is always drawn on the dark ground, so its faces take the brain's own fixed hues, as the Mac's do. */
const FACE_INKS = ["#4C8DFF", "#2DD4BF", "#FF8A3D", "#4ADE80", "#F472B6", "#A78BFA"] as const;

/** A colour for a name, by the same FNV hash the brain places by, so a person keeps their colour. */
export function faceInk(name: string): string {
  return FACE_INKS[hashOf(name.trim().toLowerCase()) % FACE_INKS.length]!;
}

/** Up to two initials, "@" for nobody named, as the console's avatar letters them. */
export function initialsFor(name: string): string {
  const letters = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]!.toUpperCase())
    .join("");
  return letters === "" ? "@" : letters;
}

/** Whether a node is somebody or a team of somebodies, drawn as a face rather than a dot. */
export function isFace(node: Pick<MemoryMapNode, "kind">): boolean {
  return node.kind === "person" || node.kind === "group";
}

/** How the record joins somebody to a thing, in the words a profile groups them under. */
const LINK_WORDS: Readonly<Record<string, string>> = {
  said: "Said",
  approved: "Approved",
  mentions: "Named in",
  member_of: "Member of",
  reports_to: "Reports to",
};
const LINK_ORDER = ["said", "approved", "mentions", "member_of", "reports_to"];

export type ProfileGroup = { kind: string; label: string; nodes: MemoryMapNode[] };
export type Profile = { groups: ProfileGroup[]; sources: string[] };

/**
 * What a person's profile lists: the things the record joins them to, grouped
 * by how, and the systems those things and their own account came from. Only
 * stated lines count, so nothing is said of somebody the record does not say.
 */
export function profileOf(personId: string, nodes: readonly MemoryMapNode[], edges: readonly MemoryMapEdge[]): Profile {
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const grouped = new Map<string, MemoryMapNode[]>();
  for (const edge of edges) {
    const other = edge.from === personId ? edge.to : edge.to === personId ? edge.from : undefined;
    if (other === undefined) continue;
    const node = byId.get(other);
    if (node === undefined) continue;
    const list = grouped.get(edge.kind) ?? [];
    if (!list.some((each) => each.id === node.id)) list.push(node);
    grouped.set(edge.kind, list);
  }
  const groups = [...grouped.entries()]
    .sort(([a], [b]) => rank(a) - rank(b) || a.localeCompare(b))
    .map(([kind, list]) => ({ kind, label: LINK_WORDS[kind] ?? "Linked", nodes: list.sort((a, b) => a.label.localeCompare(b.label)) }));
  const sources = new Set<string>();
  const own = byId.get(personId)?.system;
  if (own !== undefined) sources.add(own);
  for (const group of groups) for (const node of group.nodes) if (node.system !== undefined) sources.add(node.system);
  return { groups, sources: [...sources].sort() };
}

function rank(kind: string): number {
  const at = LINK_ORDER.indexOf(kind);
  return at === -1 ? LINK_ORDER.length : at;
}
