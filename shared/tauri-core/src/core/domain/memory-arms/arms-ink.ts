/**
 * What the brain map is drawn in. The Mac draws the brain on the console's dark ground in either appearance, so the
 * ink here is fixed rather than read from the theme: `Memnox.Console.Brain` in the Mac's DesignSystem.swift, value for
 * value. The console's blue is the apps' glow, the rules ring is gold, the skills are the ink itself, and each area of
 * memory takes one of the brain's group hues, far enough apart on the wheel that eight read apart.
 */

export const ARMS_INK = {
  ink: "#FDFDFD",
  muted: "#ADADAD",
  ground: "#030303",
  border: "#313131",
  glow: "#1E86EE",
  onGlow: "#FFFFFF",
  gold: "#F5C542",
  star: "#EEF3FB",
  pulse: "#A5CCF6",
  /** The grey of the brain's outline. */
  outline: "#8A8F98",
  /** The backing behind a name, dark enough that white reads over any dot. */
  labelBacking: "#05070C",
} as const;

/** The brain's group hues in turn: notes, instructions, servers, conversations, projects, apps, team, then the unsourced grey. */
const SECTOR_HUES = ["#4C8DFF", "#F5C542", "#2DD4BF", "#FF8A3D", "#4ADE80", "#F472B6", "#A78BFA", "#9CA3AF"] as const;

export function sectorInk(index: number): string {
  return SECTOR_HUES[index % SECTOR_HUES.length]!;
}
