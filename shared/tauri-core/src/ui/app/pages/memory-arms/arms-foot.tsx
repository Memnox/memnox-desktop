import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { Brain, Minus, Pause, Play, Plus, X, type LucideIcon } from "lucide-react";

import { Pressable } from "../../../kit";
import { BrainFootLines, TourLines, tourDetail, tourName } from "../../../../core/domain/memory-brain-lines";
import { playhead, sectionAt, TOUR_LENGTH, TOUR_SECTIONS, tourSeconds, type TourClock } from "../../../../core/domain/memory-arms/arms-tour";

/**
 * The pieces along the brain's foot, each the Mac's own view in `MemoryMapView.swift`: the rounded pills, the growth
 * card, the zoom, the hints and the tour's deck, all on the console's dark card floating over the brain.
 */

/** `mapPanel`: the dark card a little see through, its hairline edge and its shadow; the radius is the caller's. */
export const MAP_PANEL = "border border-panel-edge bg-brain-panel shadow-brain-panel";

/** MapButton's glyph, Memnox.TextSize.caption at a medium weight. */
const MAP_GLYPH = 11;
const MAP_GLYPH_STROKE = 2.25;
/** A pill's glyph, at the size of its meta words. */
const PILL_GLYPH = 13;
/** The deck's play glyph and its close mark. */
const DECK_GLYPH = 13;
/** The quiet card's brain, Memnox.TextSize.body. */
const QUIET_GLYPH = 13;
/** A frame of the deck's clock, thirty a second as the Mac's MapMotion.frame. */
const DECK_FRAME_MS = 1000 / 30;
/** The rail scrubs to just short of the loop's end, so the last stretch stays the last rather than wrapping. */
const RAIL_END = 0.9999;

/** A square glyph press on the brain's chrome, the Mac's `MapButton`: lit in the accent while what it opens is open. */
export function MapButton({ icon: Icon, label, enabled = true, on = false, onPress }: { icon: LucideIcon; label: string; enabled?: boolean; on?: boolean; onPress: () => void }) {
  return (
    <Pressable
      aria-label={label}
      title={label}
      disabled={!enabled}
      onClick={onPress}
      className={`grid size-map-button shrink-0 cursor-pointer place-items-center rounded-control transition-colors hover:bg-hover disabled:cursor-default disabled:opacity-35 disabled:hover:bg-transparent ${on ? "bg-active text-primary" : "text-muted"}`}
    >
      <Icon size={MAP_GLYPH} strokeWidth={MAP_GLYPH_STROKE} aria-hidden />
    </Pressable>
  );
}

/** A rounded button along the foot, Search, Replay, Cinema or Tour, the Mac's `BrainPill`. */
export function BrainPill({ icon: Icon, title, help, enabled = true, onPress }: { icon: LucideIcon; title: string; help: string; enabled?: boolean; onPress: () => void }) {
  return (
    <Pressable
      aria-label={title}
      title={help}
      disabled={!enabled}
      onClick={onPress}
      className="flex h-control shrink-0 cursor-pointer items-center gap-1.5 rounded-full border border-panel-edge bg-card px-3 text-meta font-medium text-foreground disabled:cursor-default disabled:opacity-35"
    >
      <Icon size={PILL_GLYPH} aria-hidden />
      {title}
    </Pressable>
  );
}

/** How much of what was learned is verified, the Mac's `BrainGrowth`. */
export function BrainGrowth({ verified, total }: { verified: number; total: number }) {
  return (
    <div className={`flex w-brain-card flex-col gap-1.5 rounded-card p-3 ${MAP_PANEL}`}>
      <p className="text-body-sm font-medium tabular-nums text-foreground">{BrainFootLines.inTheBrain(total)}</p>
      <p className="text-meta tabular-nums text-muted">{BrainFootLines.verified(verified, total)}</p>
      <div className="relative h-brain-bar overflow-hidden rounded-full bg-panel-edge" aria-hidden>
        <span className="absolute inset-y-0 left-0 rounded-full bg-primary" style={{ width: `${(100 * verified) / Math.max(total, 1)}%` }} />
      </div>
    </div>
  );
}

/** The zoom in the bottom right corner, the Mac's `MapZoom`: out, Fit, and in, each out of reach at its end. */
export function MapZoom({ canOut, canIn, onOut, onFit, onIn }: { canOut: boolean; canIn: boolean; onOut: () => void; onFit: () => void; onIn: () => void }) {
  return (
    <div role="group" aria-label={BrainFootLines.zoom} className={`flex items-center gap-0.5 rounded-control p-1 ${MAP_PANEL}`}>
      <MapButton icon={Minus} label={BrainFootLines.zoomOut} enabled={canOut} onPress={onOut} />
      <Pressable title={BrainFootLines.fitHelp} onClick={onFit} className="flex h-map-button cursor-pointer items-center px-2 text-meta font-medium text-foreground">
        {BrainFootLines.fit}
      </Pressable>
      <MapButton icon={Plus} label={BrainFootLines.zoomIn} enabled={canIn} onPress={onIn} />
    </div>
  );
}

/** The two hint lines under the foot, the Mac's `leftHint` or `orbsHint` and `rightHint`. */
export function BrainHints({ orbs }: { orbs: boolean }) {
  return (
    <div className="pointer-events-none flex items-center justify-between gap-2 font-code text-brain-caption text-faint">
      <span>{orbs ? BrainFootLines.orbsHint : BrainFootLines.leftHint}</span>
      <span>{BrainFootLines.rightHint}</span>
    </div>
  );
}

/** Said in the middle while the legend has taken everything off, or nothing needs attention, the Mac's `MapQuietCard`. */
export function QuietCard({ line }: { line: string }) {
  return (
    <div className={`flex max-w-(--spacing-brain-heading) flex-col items-center gap-1.5 rounded-card px-4 py-3 text-center ${MAP_PANEL}`}>
      <Brain size={QUIET_GLYPH} className="text-primary" aria-hidden />
      <p className="text-body-sm text-muted">{line}</p>
    </div>
  );
}

/** The counts the deck's lines say: the core's files, the areas, the rules, the applications and every mark. */
export type TourCounts = Parameters<typeof tourDetail>[1];

/**
 * The tour's deck, the Mac's `BrainTourDeck`: the mode it is in, large in the accent, what that mode opened, a rail
 * with a tick at each stretch to click or drag through, the play button, the time and the way out.
 */
export function TourDeck({ clock, counts, onToggle, onScrub, onLeave }: { clock: TourClock; counts: TourCounts; onToggle: () => void; onScrub: (seconds: number) => void; onLeave: () => void }) {
  const seconds = useTourSeconds(clock);
  const at = playhead(seconds);
  const part = sectionAt(seconds).part;
  const running = clock.held === undefined;
  return (
    <section aria-label={TourLines.label} onPointerDown={(event) => event.stopPropagation()} className={`flex w-brain-deck flex-col gap-1.5 rounded-control p-3 ${MAP_PANEL}`}>
      <div className="flex items-center gap-2 font-code text-brain-caption font-semibold tracking-deck text-muted">
        <span className="border-l-3 border-primary pl-1.5">{TourLines.overline}</span>
        <span className="flex-1" />
        <span className="text-faint">{TourLines.count(seconds)}</span>
        <Pressable aria-label={TourLines.leave} title={TourLines.leaveHelp} onClick={onLeave} className="cursor-pointer text-muted">
          <X size={DECK_GLYPH} aria-hidden />
        </Pressable>
      </div>
      <p className="text-brain-mode font-bold text-primary">{tourName(part)}</p>
      <p className="font-code text-brain-caption tracking-deck-detail text-muted">{tourDetail(part, counts)}</p>
      <div className="flex items-center gap-2">
        <Pressable
          aria-label={running ? TourLines.pause : TourLines.play}
          title={running ? TourLines.pauseHelp : TourLines.playHelp}
          onClick={onToggle}
          className="grid size-brain-play shrink-0 cursor-pointer place-items-center rounded-full bg-primary text-foreground"
        >
          {running ? <Pause size={DECK_GLYPH} fill="currentColor" aria-hidden /> : <Play size={DECK_GLYPH} fill="currentColor" aria-hidden />}
        </Pressable>
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <TourRail at={at} onScrub={onScrub} />
          <div className="flex items-center justify-between font-code text-brain-caption text-faint">
            <span>{TourLines.clock(at)}</span>
            <span>{TourLines.rail}</span>
          </div>
        </div>
      </div>
    </section>
  );
}

/** The playhead now, ticking at the Mac's frame rate while the tour runs and still while it is held. */
function useTourSeconds(clock: TourClock): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (clock.held !== undefined) return;
    const tick = window.setInterval(() => setNow(Date.now()), DECK_FRAME_MS);
    return () => window.clearInterval(tick);
  }, [clock]);
  return tourSeconds(clock, clock.held === undefined ? Math.max(now, clock.started) : now);
}

/** The rail: what has played in the accent, a tick where each stretch begins, and the knob, clicked or dragged through. */
function TourRail({ at, onScrub }: { at: number; onScrub: (seconds: number) => void }) {
  const rail = useRef<HTMLDivElement>(null);
  const share = at / TOUR_LENGTH;
  const scrub = (event: ReactPointerEvent<HTMLDivElement>) => {
    const box = rail.current?.getBoundingClientRect();
    if (box === undefined) return;
    onScrub(Math.min(Math.max((event.clientX - box.left) / Math.max(box.width, 1), 0), RAIL_END) * TOUR_LENGTH);
  };
  return (
    <div
      ref={rail}
      role="slider"
      aria-label={TourLines.time}
      aria-valuemin={0}
      aria-valuemax={TOUR_LENGTH}
      aria-valuenow={Math.floor(at)}
      aria-valuetext={TourLines.timeValue(at)}
      onPointerDown={(event) => {
        event.currentTarget.setPointerCapture(event.pointerId);
        scrub(event);
      }}
      onPointerMove={(event) => {
        if (event.currentTarget.hasPointerCapture(event.pointerId)) scrub(event);
      }}
      className="relative h-brain-rail cursor-pointer"
    >
      <span className="absolute inset-x-0 top-1/2 h-0.5 -translate-y-1/2 bg-panel-edge" />
      <span className="absolute left-0 top-1/2 h-0.5 -translate-y-1/2 bg-primary" style={{ width: `${share * 100}%` }} />
      {TOUR_SECTIONS.slice(1).map((section) => (
        <span key={section.start} className="absolute top-1/2 h-brain-tick w-px -translate-y-1/2 bg-faint" style={{ left: `${(section.start / TOUR_LENGTH) * 100}%` }} />
      ))}
      <span className="absolute top-1/2 size-brain-knob -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-primary bg-background" style={{ left: `${share * 100}%` }} />
    </div>
  );
}
