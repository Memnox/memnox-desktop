
import type { ArmsModel, ArmsSector } from "../../../../core/domain/memory-arms/arms-model";
import { ARMS_INK } from "../../../../core/domain/memory-arms/arms-ink";

/** The four layers from the core out, each with the mark the canvas draws it in. */
const LAYERS = [
  { name: "Skills", says: "handed to every agent, round AGENTS.md", mark: "star" },
  { name: "Memory", says: "what the record holds, a cluster per source", mark: "band" },
  { name: "Rules", says: "the rules in force, on the gold ring", mark: "ring" },
  { name: "Applications", says: "the systems that deliver it, numbered", mark: "tile" },
] as const;

type Mark = (typeof LAYERS)[number]["mark"];

function LayerMark({ mark }: { mark: Mark }) {
  return (
    <svg viewBox="0 0 16 16" className="size-4 shrink-0" aria-hidden>
      {mark === "star" && <path d="M8 1 Q8.6 7.4 15 8 Q8.6 8.6 8 15 Q7.4 8.6 1 8 Q7.4 7.4 8 1Z" fill={ARMS_INK.star} />}
      {mark === "band" &&
        [3, 6, 9, 12].map((x) => <circle key={x} cx={x + 0.5} cy={8 + (x % 2)} r={1.1} fill="#4C8DFF" />)}
      {mark === "ring" && (
        <>
          <circle cx={8} cy={8} r={5} fill="none" stroke={ARMS_INK.gold} strokeWidth={1.5} />
          <circle cx={8} cy={8} r={2} fill={ARMS_INK.gold} />
        </>
      )}
      {mark === "tile" && <circle cx={8} cy={8} r={6} fill="none" stroke="#1E86EE" strokeWidth={1.4} />}
    </svg>
  );
}

/** The ARMS key: its layers, its areas as presses that light one, and what is not on it yet. */
export function ArmsLegend({
  model,
  sector,
  onSector,
}: {
  model: ArmsModel;
  sector: string | undefined;
  onSector: (key: string | undefined) => void;
}) {
  const count = (layer: string) => model.items.filter((item) => item.layer === layer && item.hub !== true).length;
  const counts: Record<string, number> = {
    Skills: count("skill"),
    Memory: count("memory"),
    Rules: count("rule"),
    Applications: count("app"),
  };
  return (
    <div className="flex flex-col gap-3 pb-2">
      <ul className="flex flex-col gap-1.5">
        {LAYERS.map((layer) => (
          <li key={layer.name} className="flex items-center gap-2 text-meta">
            <LayerMark mark={layer.mark} />
            <span className="font-medium text-foreground">{layer.name}</span>
            <span className="min-w-0 flex-1 truncate text-muted">{layer.says}</span>
            <span className="tabular-nums text-muted">{counts[layer.name]}</span>
          </li>
        ))}
      </ul>
      {model.sectors.length > 0 && <SectorList sectors={model.sectors} sector={sector} onSector={onSector} />}
      <p className="text-meta leading-relaxed text-muted">
        The gold ring holds rules in force. Routines come later, since Memnox has no routines engine yet.
      </p>
    </div>
  );
}

export function SectorList({
  sectors,
  sector,
  onSector,
}: {
  sectors: readonly ArmsSector[];
  sector: string | undefined;
  onSector: (key: string | undefined) => void;
}) {
  return (
    <ul className="flex flex-wrap gap-1.5">
      {sectors.map((each) => (
        <li key={each.key}>
          <button
            type="button"
            aria-pressed={sector === each.key}
            onClick={() => onSector(sector === each.key ? undefined : each.key)}
            className={`flex items-center gap-1.5 rounded-lg border px-2 py-1 text-meta transition-colors ${
              sector === each.key ? "border-primary bg-hover text-foreground" : "border-panel-edge bg-card text-muted hover:text-foreground"
            }`}
          >
            <span className="size-2 rounded-full" style={{ background: each.ink }} aria-hidden />
            {each.label}
            <span className="tabular-nums">{each.count}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
