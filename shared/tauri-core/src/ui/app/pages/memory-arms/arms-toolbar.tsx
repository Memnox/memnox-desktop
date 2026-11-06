
import { Minus, Plus, RotateCcw, Search } from "lucide-react";

import { Pressable, Slider, Switch } from "../../../kit";
import { ArmsLines } from "../../../../core/domain/memory-brain-lines";

import type { ArmsMode } from "../../../../core/domain/memory-arms/arms-scene";

const MODES: readonly { mode: ArmsMode; label: string }[] = [
  { mode: "brain", label: "Brain map" },
  { mode: "orbs", label: "3D orbs" },
  { mode: "timeline", label: "Timeline" },
];

export const SPEED = { least: 0.25, most: 2, step: 0.25 } as const;

const CHIP = "flex items-center gap-1 rounded-xl border border-panel-edge bg-card/95 p-1 backdrop-blur";
const ICON_BUTTON = "rounded-lg p-1.5 text-muted transition-colors hover:bg-hover hover:text-foreground";

/** The key that opens the search, shown on its button as the Mac's brain shows it. */
const SEARCH_KEY = "/";

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

/** The ARMS map's own controls, top right under the count in view, as the Mac stacks them: motion and its speed, the view, the search button, and the zoom. */
export function ArmsToolbar(props: ToolbarProps) {
  return (
    <div
      onPointerDown={(event) => event.stopPropagation()}
      className="pointer-events-none flex flex-wrap items-center justify-end gap-2 [&>*]:pointer-events-auto"
    >
      <div className={`${CHIP} px-2`}>
        <Switch on={props.motion && !props.reduced} label={ArmsLines.motion} disabled={props.reduced} onChange={props.onMotion} />
        <span className="text-meta text-muted">{ArmsLines.motion}</span>
        <Slider
          label={ArmsLines.motionSpeed}
          min={SPEED.least}
          max={SPEED.most}
          step={SPEED.step}
          value={props.speed}
          disabled={!props.motion || props.reduced}
          onValue={props.onSpeed}
          className="w-20"
        />
        <span className="w-8 text-meta tabular-nums text-muted">{ArmsLines.speed(props.speed)}</span>
        <Pressable aria-label={ArmsLines.replay} onClick={props.onReplay} className={ICON_BUTTON}>
          <RotateCcw className="size-4" aria-hidden />
        </Pressable>
      </div>

      <div className={CHIP} role="radiogroup" aria-label={ArmsLines.view}>
        {MODES.map((each) => (
          <Pressable
            key={each.mode}
            role="radio"
            aria-checked={props.mode === each.mode}
            onClick={() => props.onMode(each.mode)}
            className={`rounded-lg px-2.5 py-1 text-meta font-medium transition-colors ${
              props.mode === each.mode ? "bg-hover text-foreground" : "text-muted hover:text-foreground"
            }`}
          >
            {each.label}
          </Pressable>
        ))}
      </div>

      <div className={CHIP}>
        <Pressable aria-label={ArmsLines.search} onClick={props.onSearch} className={`${ICON_BUTTON} flex items-center gap-1.5`}>
          <Search className="size-4" aria-hidden />
          <kbd className="rounded border border-panel-edge px-1.5 text-label text-muted">{SEARCH_KEY}</kbd>
        </Pressable>
      </div>

      <div className={CHIP}>
        <Pressable aria-label={ArmsLines.zoomOut} onClick={props.onZoomOut} className={ICON_BUTTON}>
          <Minus className="size-4" aria-hidden />
        </Pressable>
        <Pressable onClick={props.onFit} className="rounded-lg px-2 py-1 text-meta font-medium text-muted hover:bg-hover hover:text-foreground">
          {ArmsLines.fit}
        </Pressable>
        <Pressable aria-label={ArmsLines.zoomIn} onClick={props.onZoomIn} className={ICON_BUTTON}>
          <Plus className="size-4" aria-hidden />
        </Pressable>
      </div>
    </div>
  );
}
