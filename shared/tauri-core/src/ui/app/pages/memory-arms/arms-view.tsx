import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";

import type { Route } from "../../../../core/domain/destinations";
import { anchorCard } from "../../../../core/domain/memory-arms/arms-anchor";
import { timelineFrame } from "../../../../core/domain/memory-arms/arms-lanes";
import { linksOf } from "../../../../core/domain/memory-arms/arms-links";
import { armsModel, firstMatch, matching, type ArmsInput, type ArmsItem } from "../../../../core/domain/memory-arms/arms-model";
import type { MemoryMap } from "../../../../core/domain/memory-arms/arms-node";
import type { ArmsMode } from "../../../../core/domain/memory-arms/arms-scene";
import { ArmsCard, type ArmsRule, type ArmsSkill } from "./arms-detail";
import type { ArmsEngine, EngineProps, Hovered } from "./arms-engine";
import { ArmsLegend, SectorList } from "./arms-legend";
import { ArmsSearch } from "./arms-search";
import { ArmsStage } from "./arms-stage";
import { ArmsToolbar } from "./arms-toolbar";
import { ArmsTooltip } from "./arms-tooltip";
import { BRAIN_HEADING, brainStats, inViewLine } from "../../../../core/domain/memory-brain-lines";
import { usePrefersReducedMotion } from "./use-reduced-motion";
import "./arms.css";

const ZOOM_STEP = 1.3;

/** A key the brain answers while no field has it, so typing a slash into a search box stays the person's. */
function useBrainKey(key: string, act: (() => void) | null): void {
  useEffect(() => {
    if (act === null) return;
    const press = (event: KeyboardEvent) => {
      const target = event.target;
      if (target instanceof HTMLElement && (target.isContentEditable || target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) return;
      if (event.key !== key || event.metaKey || event.ctrlKey || event.altKey) return;
      event.preventDefault();
      act();
    };
    window.addEventListener("keydown", press);
    return () => window.removeEventListener("keydown", press);
  }, [key, act]);
}

/**
 * Memory drawn as the brain, ported from the cloud console's ARMS map: the instruction files and the skills at the
 * centre, each area of memory a packed cluster round its own hub, the rules in force on a gold ring, and the apps and
 * servers that feed it outside. A pick opens a card beside its mark that follows it, with the brain still live behind;
 * the search is a capsule in the middle. Everything it draws is a read the daemon answered.
 */
export function ArmsView({
  map,
  input,
  skills,
  rules,
  go,
  nodeCard,
  aside,
  bar,
  foot,
}: {
  map: MemoryMap;
  input: ArmsInput;
  skills: readonly ArmsSkill[];
  rules: readonly ArmsRule[];
  go?: (route: Route) => void;
  /** The memory page's own details for a node it knows, a fact or a document. */
  nodeCard: (nodeId: string, onClose: () => void) => ReactNode;
  /** A line under the legend saying what the picture stands on, where it is not whole and live. */
  aside?: string;
  /** The page's filters, laid along the top left as the Mac lays them, with the view's controls to their right. */
  bar?: ReactNode;
  /** The page's own lines under the heading's counts. */
  foot?: ReactNode;
}) {
  const reduced = usePrefersReducedMotion();
  const [mode, setMode] = useState<ArmsMode>("brain");
  const [motion, setMotion] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [query, setQuery] = useState("");
  const [sector, setSector] = useState<string | undefined>(undefined);
  const [picked, setPicked] = useState<ArmsItem | undefined>(undefined);
  const [searching, setSearching] = useState(false);
  const [hovered, setHovered] = useState<Hovered | undefined>(undefined);
  const engine = useRef<ArmsEngine | undefined>(undefined);

  const model = useMemo(() => armsModel(input), [input]);
  const links = useMemo(() => linksOf(model, map.edges), [model, map.edges]);
  const timeline = useMemo(() => timelineFrame(model.items, model.sectors), [model]);
  const matches = useMemo(() => matching(model.items, query), [model, query]);
  const arrivals = useArrivals(map);
  const props = useMemo<EngineProps>(
    () => ({ mode, motion, speed, reduced, sector, selected: picked?.id, matches }),
    [mode, motion, speed, reduced, sector, picked, matches],
  );

  useBrainKey("/", useCallback(() => setSearching(true), []));
  useBrainKey("ArrowLeft", useCallback(() => engine.current?.panBy(-1, 0), []));
  useBrainKey("ArrowRight", useCallback(() => engine.current?.panBy(1, 0), []));
  useBrainKey("ArrowUp", useCallback(() => engine.current?.panBy(0, -1), []));
  useBrainKey("ArrowDown", useCallback(() => engine.current?.panBy(0, 1), []));
  useBrainKey("Escape", useMemo(() => (picked === undefined ? null : () => setPicked(undefined)), [picked]));
  const { card, pointer, place } = useAnchoredCard(engine, picked);
  useEffect(() => {
    if (picked !== undefined && !model.items.some((item) => item.id === picked.id)) setPicked(undefined);
  }, [model, picked]);

  const closeSearch = (): void => {
    setSearching(false);
    setQuery("");
  };
  const openFirst = (): void => {
    const found = firstMatch(model.items, matches);
    if (found !== undefined) setPicked(found);
  };
  const stats = useMemo(() => brainStats(map, input.apps.length), [map, input.apps]);
  const frame = { width: engine.current?.width ?? 0, height: engine.current?.height ?? 0 };

  return (
    <div className="mx-brain absolute inset-0 overflow-hidden rounded-xl border border-panel-edge">
      <ArmsStage
        model={model}
        links={links}
        timeline={timeline}
        props={props}
        arrivals={arrivals}
        onEngine={(made) => {
          engine.current = made;
          if (made !== undefined) made.onFrame = () => place.current();
        }}
        onPick={(item) => {
          setPicked(item);
          /* An app lights the area it delivered, so its tile and its memory read as one. */
          if (item?.layer === "app" && item.sector !== undefined) setSector(item.sector);
        }}
        onSector={setSector}
        onHover={setHovered}
      />
      {model.empty && <EmptyBrain />}
      {hovered !== undefined && hovered.item.id !== picked?.id && <ArmsTooltip hovered={hovered} model={model} links={links} frame={frame} />}
      {searching && <ArmsSearch query={query} onQuery={setQuery} matches={matches.size} onOpen={openFirst} onClose={closeSearch} />}
      {/* The bar and the view's controls along the top, then the heading and its counts, as the Mac's overlays stand. */}
      <div className="pointer-events-none absolute inset-x-4 top-4 z-300 flex flex-col gap-3">
        <div className="flex items-start gap-2">
          <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-auto flex min-w-0 flex-col gap-1.5">
            {bar}
          </div>
          <span className="min-w-2 flex-1" />
          <div className="flex shrink-0 flex-col items-end gap-1.5">
            <p className="font-mono text-caption text-muted">{inViewLine(model.items.length)}</p>
            <ArmsToolbar
        mode={mode}
        onMode={setMode}
        motion={motion}
        onMotion={setMotion}
        speed={speed}
        onSpeed={setSpeed}
        reduced={reduced}
        onSearch={() => setSearching(true)}
        onZoomOut={() => engine.current?.zoomBy(1 / ZOOM_STEP)}
        onFit={() => engine.current?.fit()}
        onZoomIn={() => engine.current?.zoomBy(ZOOM_STEP)}
        onReplay={() => engine.current?.replay()}
            />
          </div>
        </div>
        <BrainHeading stats={stats} foot={foot} />
      </div>
      {model.sectors.length > 1 && (
        <div onPointerDown={(event) => event.stopPropagation()} className="absolute inset-x-0 bottom-4 z-300 flex justify-center px-40 max-[900px]:px-4">
          <SectorList sectors={model.sectors} sector={sector} onSector={setSector} />
        </div>
      )}
      {!model.empty && (
        <details onPointerDown={(event) => event.stopPropagation()} className="absolute bottom-4 left-4 z-300 max-w-72 rounded-xl border border-panel-edge bg-card/95 p-3 text-meta backdrop-blur">
          <summary className="mx-focus cursor-pointer list-none font-medium text-muted select-none">Legend</summary>
          <div className="flex flex-col gap-3 pt-3">
            <ArmsLegend model={model} sector={sector} onSector={setSector} />
            {aside !== undefined && <p className="text-label leading-relaxed text-muted">{aside}</p>}
          </div>
        </details>
      )}
      {picked !== undefined && (
        /* Placed by the engine's frame rather than by React, so it follows its mark without a render per frame. */
        <div
          ref={card}
          onPointerDown={(event) => event.stopPropagation()}
          style={{ visibility: "hidden" }}
          className="absolute left-0 top-0 z-400 w-80 max-w-[calc(100%-2rem)] will-change-transform"
        >
          <span ref={pointer} aria-hidden className="absolute size-3 rotate-45 border border-panel-edge bg-card" />
          <ArmsCard
            item={picked}
            model={model}
            links={links}
            nodes={map.nodes}
            edges={map.edges}
            skills={skills}
            rules={rules}
            apps={input.apps}
            {...(go === undefined ? {} : { go })}
            nodeCard={(id) => nodeCard(id, () => setPicked(undefined))}
            onOpen={setPicked}
            onSector={(key) => {
              setSector(key);
              setPicked(undefined);
            }}
            onClose={() => setPicked(undefined)}
          />
        </div>
      )}
    </div>
  );
}

/** What a read again brought, as item ids for the engine to send travelling in; the first read lights nothing. */
function useArrivals(map: MemoryMap): { ids: string[]; stamp: number } {
  const before = useRef<Set<string> | undefined>(undefined);
  const [arrived, setArrived] = useState<{ ids: string[]; stamp: number }>({ ids: [], stamp: 0 });
  useEffect(() => {
    const ids = new Set(map.nodes.map((node) => node.id));
    const known = before.current;
    before.current = ids;
    if (known === undefined) return;
    const fresh = [...ids].filter((id) => !known.has(id));
    if (fresh.length > 0) setArrived((was) => ({ ids: fresh.map((id) => `memory:${id}`), stamp: was.stamp + 1 }));
  }, [map]);
  return arrived;
}

/** Half the pointer's side, so its middle lands on the card's edge. */
const POINTER_HALF = 6;

/**
 * The detail card held beside its mark: each painted frame, and whenever the
 * card's own size changes, it is placed by `anchorCard` from the mark's screen
 * point, flipping to whichever side keeps it inside the canvas.
 */
function useAnchoredCard(engine: { readonly current: ArmsEngine | undefined }, picked: ArmsItem | undefined) {
  const card = useRef<HTMLDivElement>(null);
  const pointer = useRef<HTMLSpanElement>(null);
  const pickedId = useRef<string | undefined>(undefined);
  pickedId.current = picked?.id;

  const placeNow = useCallback(() => {
    const made = engine.current;
    const box = card.current;
    if (made === undefined || box === null || pickedId.current === undefined) return;
    const at = made.index.get(pickedId.current);
    if (at === undefined) return;
    const anchor = anchorCard(
      { x: made.sx[at] ?? 0, y: made.sy[at] ?? 0, r: made.sr[at] ?? 0 },
      { width: box.offsetWidth, height: box.offsetHeight },
      { width: made.width, height: made.height },
    );
    box.style.transform = `translate(${Math.round(anchor.left)}px, ${Math.round(anchor.top)}px)`;
    box.style.visibility = anchor.visible ? "visible" : "hidden";
    const tip = pointer.current;
    if (tip !== null) {
      tip.style.left = `${anchor.pointer.x - POINTER_HALF}px`;
      tip.style.top = `${anchor.pointer.y - POINTER_HALF}px`;
    }
  }, [engine]);
  const place = useRef(placeNow);
  place.current = placeNow;

  useLayoutEffect(() => {
    placeNow();
    engine.current?.wake();
    const box = card.current;
    if (box === null) return;
    const sizes = new ResizeObserver(() => placeNow());
    sizes.observe(box);
    return () => sizes.disconnect();
  }, [picked, placeNow, engine]);

  return { card, pointer, place };
}

/** The heading over the brain's top left: what it is, the two line title, its counts and the page's own lines. */
function BrainHeading({ stats, foot }: { stats: { memories: number; sources: number; connections: number }; foot: ReactNode }) {
  const stat = (count: number, caption: string) => (
    <div className="flex flex-col gap-0.5">
      <span className="text-[26px] leading-none font-semibold tabular-nums text-foreground">{count}</span>
      <span className="font-mono text-micro font-medium tracking-[0.18em] text-faint">{caption}</span>
    </div>
  );
  return (
    <div className="flex max-w-[380px] flex-col gap-2">
      <p className="font-mono text-caption font-medium tracking-[0.18em] text-muted">{BRAIN_HEADING.overline}</p>
      <h2 className="text-[34px] leading-[1.1] font-semibold tracking-[-0.014em]">
        <span className="block text-foreground">{BRAIN_HEADING.title}</span>
        <span className="block text-faint">{BRAIN_HEADING.titleQuiet}</span>
      </h2>
      <p className="text-body-sm text-muted">{BRAIN_HEADING.subline}</p>
      <div className="flex items-start gap-5 pt-1">
        {stat(stats.memories, BRAIN_HEADING.memories)}
        {stat(stats.sources, BRAIN_HEADING.sources)}
        {stat(stats.connections, BRAIN_HEADING.connections)}
      </div>
      {foot !== undefined && (
        <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-auto flex flex-col gap-1.5">
          {foot}
        </div>
      )}
    </div>
  );
}

/** What an empty brain says, in place of a silhouette drawn round nothing. */
function EmptyBrain() {
  return (
    <div className="pointer-events-none absolute inset-0 z-200 flex items-center justify-center p-8">
      <div className="max-w-sm text-center">
        <p className="text-body font-semibold text-foreground">Nothing in the brain yet</p>
        <p className="mt-1.5 text-body-sm leading-relaxed text-muted">
          It is built from what this computer's memory holds. Add a source or confirm what Learn read, and each area grows here as its first memory arrives.
        </p>
      </div>
    </div>
  );
}
