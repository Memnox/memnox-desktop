
import { Minus, Plus, RotateCcw, Search } from "lucide-react";

import { Switch } from "../../../settings/kit";

import type { ArmsMode } from "../../../../core/domain/memory-arms/arms-scene";

const MODES: readonly { mode: ArmsMode; label: string }[] = [
  { mode: "brain", label: "Brain map" },
  { mode: "orbs", label: "3D orbs" },
  { mode: "timeline", label: "Timeline" },
];

export const SPEED = { least: 0.25, most: 2, step: 0.25 } as const;

const CHIP = "flex items-center gap-1 rounded-xl border border-panel-edge bg-card/95 p-1 backdrop-blur";
const ICON_BUTTON = "rounded-lg p-1.5 text-muted transition-colors hover:bg-hover hover:text-foreground";

type ToolbarProps = {
  mode: ArmsMode;
  onMode: (mode: ArmsMode) => void;
  motion: boolean;
  onMotion: (on: boolean) => void;
  speed: number;
  onSpeed: (speed: number) => void;
  /** Motion is calm fades only here, whatever the switch says. */
  reduced: boolean;
  /** Opens the search capsule in the middle of the brain. */
  onSearch: () => void;
  onZoomOut: () => void;
  onFit: () => void;
  onZoomIn: () => void;
  onReplay: () => void;
};

/** The ARMS map's own controls, top right: motion and its speed, the view, the search button, and the zoom. */
export function ArmsToolbar(props: ToolbarProps) {
  return (
    <div
      onPointerDown={(event) => event.stopPropagation()}
      className="pointer-events-none absolute right-4 top-4 z-300 flex max-w-[calc(100%-2rem)] flex-wrap items-center justify-end gap-2 [&>*]:pointer-events-auto"
    >
      <div className={`${CHIP} px-2`}>
        <Switch on={props.motion && !props.reduced} label="Motion" disabled={props.reduced} onChange={props.onMotion} />
        <span className="text-meta text-muted">Motion</span>
        <input
          type="range"
          aria-label="Motion speed"
          min={SPEED.least}
          max={SPEED.most}
          step={SPEED.step}
          value={props.speed}
          disabled={!props.motion || props.reduced}
          onChange={(event) => props.onSpeed(Number(event.target.value))}
          className="w-20 accent-[var(--color-primary)] disabled:opacity-40"
        />
        <span className="w-8 text-meta tabular-nums text-muted">{props.speed}x</span>
        <button type="button" aria-label="Replay the opening" onClick={props.onReplay} className={ICON_BUTTON}>
          <RotateCcw className="size-4" aria-hidden />
        </button>
      </div>

      <div className={CHIP} role="radiogroup" aria-label="View">
        {MODES.map((each) => (
          <button
            key={each.mode}
            type="button"
            role="radio"
            aria-checked={props.mode === each.mode}
            onClick={() => props.onMode(each.mode)}
            className={`rounded-lg px-2.5 py-1 text-meta font-medium transition-colors ${
              props.mode === each.mode ? "bg-hover text-foreground" : "text-muted hover:text-foreground"
            }`}
          >
            {each.label}
          </button>
        ))}
      </div>

      <div className={CHIP}>
        <button type="button" aria-label="Search the brain" onClick={props.onSearch} className={`${ICON_BUTTON} flex items-center gap-1.5`}>
          <Search className="size-4" aria-hidden />
          <kbd className="rounded border border-panel-edge px-1.5 text-label text-muted">/</kbd>
        </button>
      </div>

      <div className={CHIP}>
        <button type="button" aria-label="Zoom out" onClick={props.onZoomOut} className={ICON_BUTTON}>
          <Minus className="size-4" aria-hidden />
        </button>
        <button type="button" onClick={props.onFit} className="rounded-lg px-2 py-1 text-meta font-medium text-muted hover:bg-hover hover:text-foreground">
          Fit
        </button>
        <button type="button" aria-label="Zoom in" onClick={props.onZoomIn} className={ICON_BUTTON}>
          <Plus className="size-4" aria-hidden />
        </button>
      </div>
    </div>
  );
}
