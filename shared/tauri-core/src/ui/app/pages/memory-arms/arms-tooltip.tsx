
import { markUrl, QUIET_DOT } from "./arms-support";

import { faceInk, initialsFor } from "../../../../core/domain/memory-arms/arms-faces";
import type { Hovered } from "./arms-engine";
import type { ArmsItem, ArmsModel } from "../../../../core/domain/memory-arms/arms-model";

/** What a mark is, in the words its card would use. */
export function kindWord(item: ArmsItem): string {
  if (item.core === true) return "Instructions every agent reads";
  if (item.hub === true) return item.nodeId === undefined ? "Area" : "Index of memories";
  if (item.layer === "skill") return "Skill";
  if (item.layer === "rule") return "Rule in force";
  if (item.layer === "app") return "Connected system";
  switch (item.kind) {
    case "person":
      return "Person";
    case "group":
      return "Team";
    case "document":
      return "Source";
    case "passage":
      return "Passage";
    case "conversation":
      return "Conversation";
    default:
      return "Memory";
  }
}

/** How far the card stands off its mark, and the least it keeps from the brain's edges. */
const OFFSET = 12;
const EDGE = 8;
/** `MapMetrics.tipWidth` and `tipTall`: the card's width, and the height kept free under it at the foot. */
const WIDTH = 220;
const TIP_TALL = 96;
/** The card's top sits this far above the mark's centre, so its first line reads beside the mark. */
const TIP_RISE = 28;

/** The hover card beside a mark: its face or mark, its name, what it is, its area and how many things it links to. */
export function ArmsTooltip({
  hovered,
  model,
  links,
  frame,
}: {
  hovered: Hovered;
  model: ArmsModel;
  links: ReadonlyMap<string, string[]>;
  frame: { width: number; height: number };
}) {
  const { item } = hovered;
  const area = model.sectors.find((sector) => sector.key === item.sector);
  const linked = new Set(links.get(item.id) ?? []).size;
  const right = hovered.x + hovered.radius + OFFSET + WIDTH < frame.width;
  const left = right ? hovered.x + hovered.radius + OFFSET : hovered.x - hovered.radius - OFFSET - WIDTH;
  const top = Math.max(EDGE, Math.min(frame.height - TIP_TALL, hovered.y - TIP_RISE));
  const person = item.kind === "person" || item.kind === "group";

  return (
    <div
      role="tooltip"
      style={{ left: Math.max(EDGE, left), top, width: WIDTH }}
      className="pointer-events-none absolute z-300 flex items-start gap-2.5 rounded-xl border border-panel-edge bg-card/95 p-3 shadow-brain-panel backdrop-blur"
    >
      {person ? (
        <span
          className="flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full text-label font-semibold text-white"
          style={{ background: faceInk(item.label) }}
          aria-hidden
        >
          {initialsFor(item.label)}
        </span>
      ) : item.logo !== undefined ? (
        <img src={markUrl(item.logo)} alt="" className="size-8 shrink-0 rounded-full border border-panel-edge bg-card object-contain p-1" aria-hidden />
      ) : (
        <span className="mt-1 size-3 shrink-0 rounded-full" style={{ background: area?.ink ?? QUIET_DOT }} aria-hidden />
      )}
      <div className="min-w-0">
        <p className="break-words text-body-sm font-semibold leading-snug text-foreground">{item.label}</p>
        <p className="mt-0.5 text-meta text-muted">
          {kindWord(item)}
          {area !== undefined && item.hub !== true ? ` in ${area.label}` : ""}
        </p>
        <p className="mt-1 text-label text-muted">
          {item.holds !== undefined && item.core !== true ? `${item.holds} held, ` : ""}
          {linked === 0 ? "No links" : `${linked} ${linked === 1 ? "link" : "links"}`}
        </p>
      </div>
    </div>
  );
}
