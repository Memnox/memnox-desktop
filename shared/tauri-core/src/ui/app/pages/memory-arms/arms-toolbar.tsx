import { Brain, CalendarRange, Hexagon, Pause, Sparkles, type LucideIcon } from "lucide-react";

import { Pressable, Slider } from "../../../kit";
import { BRAIN_SPEED, BRAIN_VIEWS, BrainViewLines } from "../../../../core/domain/memory-brain-lines";
import type { ArmsMode } from "../../../../core/domain/memory-arms/arms-scene";
import { MapButton, MAP_PANEL } from "./arms-foot";

/** Each view's mark, the nearest to the Mac's `brain`, `circle.hexagongrid` and `calendar.day.timeline.left`. */
const VIEW_ICON: Record<ArmsMode, LucideIcon> = { brain: Brain, orbs: Hexagon, timeline: CalendarRange };
/** KitLabel's console glyph, Memnox.TextSize.callout. */
const VIEW_GLYPH = 14;
/** The speed slider moves without notches, as the Mac's does. */
const SPEED_STEP = 0.05;

type ToolbarProps = {
  mode: ArmsMode;
  onMode: (mode: ArmsMode) => void;
  motion: boolean;
  onMotion: (on: boolean) => void;
  speed: number;
  onSpeed: (speed: number) => void;
  /** Reduce Motion is on, so nothing moves on its own and there is no speed to set. */
  reduced: boolean;
};

/** The view's own controls along the top right, the Mac's `BrainViewControls`: the three views, then Motion with its speed. */
export function ArmsToolbar(props: ToolbarProps) {
  return (
    <div
      role="group"
      aria-label={BrainViewLines.label}
      onPointerDown={(event) => event.stopPropagation()}
      className={`pointer-events-auto flex items-center gap-1 p-1 ${MAP_PANEL} rounded-control`}
    >
      {BRAIN_VIEWS.map((each) => {
        const on = props.mode === each.mode;
        const Icon = VIEW_ICON[each.mode];
        return (
          <Pressable
            key={each.mode}
            aria-pressed={on}
            onClick={() => props.onMode(each.mode)}
            className={`flex h-map-button cursor-pointer items-center gap-1.5 rounded-control px-2 text-meta ${on ? "bg-active font-medium text-foreground" : "text-muted"}`}
          >
            <Icon size={VIEW_GLYPH} aria-hidden />
            {each.title}
          </Pressable>
        );
      })}
      {!props.reduced && (
        <>
          <Rule />
          <MapButton icon={props.motion ? Sparkles : Pause} label={BrainViewLines.motion(props.motion)} on={props.motion} onPress={() => props.onMotion(!props.motion)} />
          <Slider
            label={BrainViewLines.motionSpeed}
            min={BRAIN_SPEED.slowest}
            max={BRAIN_SPEED.quickest}
            step={SPEED_STEP}
            value={props.speed}
            disabled={!props.motion}
            onValue={props.onSpeed}
            className="w-map-slider"
          />
        </>
      )}
    </div>
  );
}

/** The hairline between groups of the view's controls. */
function Rule() {
  return <span aria-hidden className="h-map-divider w-px bg-panel-edge" />;
}
