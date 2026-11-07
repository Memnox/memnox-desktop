
import { useEffect, useRef } from "react";

import { MOST_PIXEL_RATIO, paintFor } from "./arms-support";

import { ArmsEngine, type EngineProps, type Hovered } from "./arms-engine";
import type { TimelineFrame } from "../../../../core/domain/memory-arms/arms-lanes";
import type { ArmsItem, ArmsModel } from "../../../../core/domain/memory-arms/arms-model";

/** Travel under this is a click rather than a drag. */
const CLICK_SLOP = 4;
const WHEEL_ZOOM = 0.0015;

/**
 * The canvas the ARMS map is drawn on, and the gestures over it. One engine
 * per mount; React only hands it props, so a hover or a twinkle never renders.
 */
export function ArmsStage({
  model,
  links,
  timeline,
  props,
  arrivals,
  onEngine,
  onPick,
  onSector,
  onHover,
}: {
  model: ArmsModel;
  links: Map<string, string[]>;
  timeline: TimelineFrame;
  props: EngineProps;
  /** Item ids that just arrived, with a stamp so the same ids twice still travel. */
  arrivals: { ids: string[]; stamp: number };
  onEngine: (engine: ArmsEngine | undefined) => void;
  onPick: (item: ArmsItem | undefined) => void;
  onSector: (key: string | undefined) => void;
  /** The mark under the pointer, for the hover card; undefined when it leaves. */
  onHover: (hovered: Hovered | undefined) => void;
}) {
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const probe = useRef<HTMLSpanElement>(null);
  const engine = useRef<ArmsEngine | undefined>(undefined);
  /* The latest callback, so the engine made once still reaches the view's current state. */
  const hoverRef = useRef(onHover);
  hoverRef.current = onHover;

  useEffect(() => {
    if (canvas.current === null || host.current === null) return;
    const family = getComputedStyle(host.current).fontFamily || "system-ui, sans-serif";
    const made = new ArmsEngine(canvas.current, paintFor(probe.current), family);
    engine.current = made;
    made.onHover = (hovered) => hoverRef.current(hovered);
    onEngine(made);
    const frame = host.current;
    const measure = () => {
      const box = frame.getBoundingClientRect();
      made.resize(box.width, box.height, Math.min(MOST_PIXEL_RATIO, window.devicePixelRatio || 1));
    };
    measure();
    const sizes = new ResizeObserver(measure);
    sizes.observe(frame);
    const visibility = () => made.setHidden(document.visibilityState === "hidden");
    document.addEventListener("visibilitychange", visibility);
    /* A theme switched while the page is open is read again, since the canvas resolves colours once. */
    const theme = new MutationObserver(() => made.setPaint(paintFor(probe.current)));
    theme.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "class"] });
    return () => {
      sizes.disconnect();
      theme.disconnect();
      document.removeEventListener("visibilitychange", visibility);
      made.dispose();
      engine.current = undefined;
      onEngine(undefined);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => engine.current?.setModel(model, links, timeline), [model, links, timeline]);
  useEffect(() => engine.current?.setProps(props), [props]);
  useEffect(() => {
    if (arrivals.ids.length > 0) engine.current?.arrive(arrivals.ids);
  }, [arrivals]);

  useWheelZoom(host, engine);
  const gesture = useRef({ down: false, x: 0, y: 0, travel: 0, at: 0 });

  return (
    <div
      ref={host}
      className="absolute inset-0 cursor-grab touch-none select-none"
      onPointerDown={(event) => {
        event.currentTarget.setPointerCapture(event.pointerId);
        gesture.current = { down: true, x: event.clientX, y: event.clientY, travel: 0, at: performance.now() };
        engine.current?.grab();
        event.currentTarget.style.cursor = "grabbing";
      }}
      onPointerMove={(event) => {
        const made = engine.current;
        if (made === undefined) return;
        const box = event.currentTarget.getBoundingClientRect();
        const was = gesture.current;
        if (!was.down) {
          const hit = made.hit(event.clientX - box.left, event.clientY - box.top);
          made.setHover(hit.item === undefined ? -1 : (made.index.get(hit.item.id) ?? -1));
          event.currentTarget.style.cursor = hit.item !== undefined || hit.sector !== undefined ? "pointer" : "grab";
          return;
        }
        const now = performance.now();
        const dx = event.clientX - was.x;
        const dy = event.clientY - was.y;
        gesture.current = { down: true, x: event.clientX, y: event.clientY, travel: was.travel + Math.hypot(dx, dy), at: now };
        if (gesture.current.travel > CLICK_SLOP) made.drag(dx, dy, (now - was.at) / 1000);
      }}
      onPointerUp={(event) => {
        const made = engine.current;
        const was = gesture.current;
        gesture.current = { ...was, down: false };
        event.currentTarget.style.cursor = "grab";
        if (made === undefined) return;
        made.release((performance.now() - was.at) / 1000);
        if (was.travel > CLICK_SLOP) return;
        const box = event.currentTarget.getBoundingClientRect();
        const hit = made.hit(event.clientX - box.left, event.clientY - box.top);
        if (hit.item !== undefined) onPick(hit.item);
        else if (hit.sector !== undefined) onSector(hit.sector === props.sector ? undefined : hit.sector);
        else {
          onPick(undefined);
          onSector(undefined);
        }
      }}
      // A double click fits the whole brain again, as the hint under the foot says.
      onDoubleClick={() => engine.current?.fit()}
      onPointerLeave={() => engine.current?.setHover(-1)}
      onPointerCancel={() => {
        gesture.current = { ...gesture.current, down: false };
        engine.current?.release(Number.POSITIVE_INFINITY);
      }}
    >
      <canvas ref={canvas} className="block size-full" aria-hidden />
      {/* Resolves theme tokens for the canvas, which cannot read a variable itself. */}
      <span ref={probe} className="hidden" />
    </div>
  );
}

/** The wheel zooms about the pointer; passive listeners cannot stop the page scrolling, so it is bound by hand. */
function useWheelZoom(host: React.RefObject<HTMLDivElement | null>, engine: React.RefObject<ArmsEngine | undefined>): void {
  useEffect(() => {
    const frame = host.current;
    if (frame === null) return;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const box = frame.getBoundingClientRect();
      engine.current?.zoomBy(Math.exp(-event.deltaY * WHEEL_ZOOM), { x: event.clientX - box.left, y: event.clientY - box.top });
    };
    frame.addEventListener("wheel", onWheel, { passive: false });
    return () => frame.removeEventListener("wheel", onWheel);
  }, [host, engine]);
}
