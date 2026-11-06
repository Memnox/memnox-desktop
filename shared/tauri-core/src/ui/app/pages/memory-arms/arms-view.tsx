import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Box, CirclePlay, Film, Search } from "lucide-react";

import type { Route } from "../../../../core/domain/destinations";
import { anchorCard } from "../../../../core/domain/memory-arms/arms-anchor";
import { ZOOM } from "../../../../core/domain/memory-arms/arms-fit";
import { timelineFrame } from "../../../../core/domain/memory-arms/arms-lanes";
import { drawnModel, drawnStats, legendRows, type LegendLayer } from "../../../../core/domain/memory-arms/arms-legend";
import { linksOf } from "../../../../core/domain/memory-arms/arms-links";
import { armsModel, firstMatch, matching, type ArmsInput, type ArmsItem } from "../../../../core/domain/memory-arms/arms-model";
import type { MemoryMap } from "../../../../core/domain/memory-arms/arms-node";
import { ARMS_MODES, type ArmsMode } from "../../../../core/domain/memory-arms/arms-scene";
import { scrubTour, toggleTour, type TourClock } from "../../../../core/domain/memory-arms/arms-tour";
import { ArmsCard, type ArmsRule, type ArmsSkill } from "./arms-detail";
import type { ArmsEngine, EngineProps, Hovered } from "./arms-engine";
import { BrainGrowth, BrainHints, BrainPill, MapZoom, QuietCard, TourDeck } from "./arms-foot";
import { BrainLegend } from "./arms-legend";
import { ArmsSearch } from "./arms-search";
import { ArmsStage } from "./arms-stage";
import { ArmsToolbar } from "./arms-toolbar";
import { ArmsTooltip } from "./arms-tooltip";
import { BRAIN_HEADING, BRAIN_KEYS, BRAIN_SPEED, BrainFootLines, inViewLine } from "../../../../core/domain/memory-brain-lines";
import { usePrefersReducedMotion } from "./use-reduced-motion";
import "./arms.css";

/** How far a zoom button or the plus and minus keys zoom, the Mac's `MapMetrics.pressZoom`. */
const PRESS_ZOOM = 1.2;
/** The zoom buttons are out of reach this near an end, so a rounding at the bound never leaves one live. */
const ZOOM_END = 1.001;

/** Whether a key went to a field rather than to the brain, so typing a slash into a search box stays the person's. */
function typing(target: EventTarget | null): boolean {
  return target instanceof HTMLElement && (target.isContentEditable || target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement);
}

/** Whether Space or Return belongs to the control that has the focus, so a focused chip or button is pressed rather than the brain. */
function pressing(event: KeyboardEvent): boolean {
  return (event.key === " " || event.key === "Enter") && event.target instanceof HTMLElement && event.target.closest("button, a, [role='button']") !== null;
}

/**
 * Memory drawn as the brain, ported from the cloud console's ARMS map and laid over as the Mac's `MemoryMapView` lays
 * it: the bar and the view's controls along the top, the heading and its counts, then the legend, Search, Replay,
 * Cinema and Tour, how full the brain is and the zoom along the foot, with the hints under them. Cinema puts every
 * overlay away until Escape, and the tour takes the brain apart and puts it back on a loop with its deck in their place.
 */
export function ArmsView({
  map,
  input,
  skills,
  rules,
  go,
  nodeCard,
  sourceAreas,
  growth,
  attention,
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
  /** Each listed source's area, which SOURCES counts while the area is drawn. */
  sourceAreas: readonly (string | undefined)[];
  /** How much of what was learned is verified, for the growth card. */
  growth: { verified: number; total: number };
  /** The record's nodes that need attention, which Only what needs attention keeps. */
  attention: ReadonlySet<string>;
  /** The page's filters, laid along the top left as the Mac lays them, with the view's controls to their right. */
  bar?: ReactNode;
  /** The page's own lines under the heading's counts. */
  foot?: ReactNode;
}) {
  const reduced = usePrefersReducedMotion();
  const [mode, setMode] = useState<ArmsMode>("brain");
  const [motion, setMotion] = useState(true);
  const [speed, setSpeed] = useState<number>(BRAIN_SPEED.normal);
  const [query, setQuery] = useState("");
  const [sector, setSector] = useState<string | undefined>(undefined);
  const [picked, setPicked] = useState<ArmsItem | undefined>(undefined);
  const [searching, setSearching] = useState(false);
  const [hovered, setHovered] = useState<Hovered | undefined>(undefined);
  const [hiddenAreas, setHiddenAreas] = useState<ReadonlySet<string>>(new Set());
  const [hiddenLayers, setHiddenLayers] = useState<ReadonlySet<LegendLayer>>(new Set());
  const [attentionOnly, setAttentionOnly] = useState(false);
  const [allLabels, setAllLabels] = useState(false);
  const [cinema, setCinema] = useState(false);
  const [tour, setTour] = useState<TourClock | undefined>(undefined);
  const [zoom, setZoom] = useState(1);
  const engine = useRef<ArmsEngine | undefined>(undefined);

  // Laid out from the whole record, so taking an area off never moves what stays.
  const whole = useMemo(() => armsModel(input), [input]);
  const cut = useMemo(
    () => ({ areas: hiddenAreas, layers: hiddenLayers, ...(attentionOnly ? { attention } : {}) }),
    [hiddenAreas, hiddenLayers, attentionOnly, attention],
  );
  const model = useMemo(() => drawnModel(whole, map, cut), [whole, map, cut]);
  const rows = useMemo(() => legendRows(whole), [whole]);
  const links = useMemo(() => linksOf(model, map.edges), [model, map.edges]);
  const timeline = useMemo(() => timelineFrame(model.items, model.sectors), [model]);
  const matches = useMemo(() => matching(model.items, query), [model, query]);
  const arrivals = useArrivals(map);
  // The idle life runs in Cinema whatever the switch says, as the Mac's does.
  const props = useMemo<EngineProps>(
    () => ({ mode, motion: motion || cinema, speed, reduced, sector, selected: picked?.id, matches, allLabels, tour }),
    [mode, motion, cinema, speed, reduced, sector, picked, matches, allLabels, tour],
  );

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
  const zoomBy = (factor: number): void => {
    const made = engine.current;
    made?.zoomBy(factor, { x: made.width / 2, y: made.height / 2 });
  };
  const startTour = (): void => {
    if (reduced) return;
    setPicked(undefined);
    setTour({ started: Date.now() });
    engine.current?.fit();
  };
  const leaveTour = (): void => setTour(undefined);
  const enterCinema = (): void => {
    setCinema(true);
    engine.current?.fit();
  };
  const replay = (): void => engine.current?.replay();
  const toggle = <Value,>(set: (change: (was: ReadonlySet<Value>) => ReadonlySet<Value>) => void, value: Value): void =>
    set((was) => {
      const next = new Set(was);
      if (!next.delete(value)) next.add(value);
      return next;
    });

  useBrainKeys({
    picked: picked !== undefined,
    touring: tour !== undefined,
    cinema,
    lit: sector !== undefined,
    close: () => setPicked(undefined),
    leaveTour,
    leaveCinema: () => setCinema(false),
    unlight: () => setSector(undefined),
    space: () => (tour === undefined ? setMotion((was) => !was) : setTour((was) => (was === undefined ? was : toggleTour(was, Date.now())))),
    search: () => setSearching(true),
    fit: () => engine.current?.fit(),
    center: () => engine.current?.center(),
    replay,
    tour: () => (tour === undefined ? startTour() : leaveTour()),
    motion: () => setMotion((was) => !was),
    view: (index) => {
      const next = ARMS_MODES[index];
      if (next !== undefined) setMode(next);
    },
    zoom: zoomBy,
    open: () => {
      const made = engine.current;
      const item = made?.model.items[made.hover];
      if (item !== undefined) setPicked(item);
    },
    walk: (step) => engine.current?.walk(step),
  });

  const stats = useMemo(() => drawnStats(model, map, sourceAreas, cut), [model, map, sourceAreas, cut]);
  const quiet = !whole.empty && model.empty ? (attentionOnly ? BrainFootLines.nothingNeedsYou : BrainFootLines.everythingHidden) : undefined;
  const frame = { width: engine.current?.width ?? 0, height: engine.current?.height ?? 0 };
  const overlays = !cinema && tour === undefined;
  const tourCounts = {
    skills: rows.layers.find((row) => row.layer === "skill")?.count ?? 0,
    areas: model.sectors.length,
    rules: rows.layers.find((row) => row.layer === "rule")?.count ?? 0,
    applications: rows.layers.find((row) => row.layer === "app")?.count ?? 0,
    marks: model.items.length,
  };

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
          if (made === undefined) return;
          made.onFrame = () => place.current();
          made.onZoom = setZoom;
        }}
        onPick={(item) => {
          setPicked(item);
          /* An app lights the area it delivered, so its tile and its memory read as one. */
          if (item?.layer === "app" && item.sector !== undefined) setSector(item.sector);
        }}
        onSector={setSector}
        onHover={setHovered}
      />
      {whole.empty && <EmptyBrain />}
      {overlays && quiet !== undefined && (
        <div className="pointer-events-none absolute inset-0 z-200 flex items-center justify-center p-8">
          <QuietCard line={quiet} />
        </div>
      )}
      {hovered !== undefined && hovered.item.id !== picked?.id && <ArmsTooltip hovered={hovered} model={model} links={links} frame={frame} />}
      {searching && !cinema && <ArmsSearch query={query} onQuery={setQuery} matches={matches.size} onOpen={openFirst} onClose={closeSearch} />}
      {overlays && (
        /* The bar and the view's controls along the top, then the heading and its counts, as the Mac's overlays stand. */
        <div className="pointer-events-none absolute inset-x-4 top-4 z-300 flex flex-col gap-3">
          <div className="flex items-start gap-2">
            <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-auto flex min-w-0 flex-col gap-1.5">
              {bar}
            </div>
            <span className="min-w-2 flex-1" />
            <div className="flex shrink-0 flex-col items-end gap-1.5">
              <p className="font-code text-brain-overline text-muted">{inViewLine(model.items.length)}</p>
              <ArmsToolbar mode={mode} onMode={setMode} motion={motion} onMotion={setMotion} speed={speed} onSpeed={setSpeed} reduced={reduced} />
            </div>
          </div>
          <BrainHeading stats={stats} foot={foot} />
        </div>
      )}
      {overlays && !whole.empty && (
        /* The legend, the four pills, how full the brain is and the zoom along the foot, with the hints between. */
        <div className="pointer-events-none absolute inset-x-4 bottom-4 z-300 flex flex-col gap-2">
          <div className="flex items-end gap-3">
            <div className="pointer-events-auto">
              <BrainLegend
                areas={rows.areas}
                layers={rows.layers}
                hiddenAreas={hiddenAreas}
                hiddenLayers={hiddenLayers}
                lit={sector}
                onLight={(key) => setSector((was) => (was === key ? undefined : key))}
                onArea={(key) => toggle(setHiddenAreas, key)}
                onLayer={(layer) => toggle(setHiddenLayers, layer)}
                attentionOnly={attentionOnly}
                onAttention={() => setAttentionOnly((was) => !was)}
                allLabels={allLabels}
                onAllLabels={() => setAllLabels((was) => !was)}
              />
            </div>
            <span className="min-w-2 flex-1" />
            <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-auto flex items-center gap-1.5">
              <BrainPill icon={Search} title={BrainFootLines.search} help={BrainFootLines.searchHelp} onPress={() => setSearching(true)} />
              <BrainPill icon={CirclePlay} title={BrainFootLines.replay} help={BrainFootLines.replayHelp} onPress={replay} />
              <BrainPill icon={Film} title={BrainFootLines.cinema} help={BrainFootLines.cinemaHelp} onPress={enterCinema} />
              <BrainPill icon={Box} title={BrainFootLines.tour} help={reduced ? BrainFootLines.tourStill : BrainFootLines.tourHelp} enabled={!reduced} onPress={startTour} />
            </div>
            <span className="min-w-2 flex-1" />
            <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-auto flex flex-col items-end gap-2">
              {growth.total > 0 && <BrainGrowth verified={growth.verified} total={growth.total} />}
              <MapZoom
                canOut={zoom > ZOOM.least * ZOOM_END}
                canIn={zoom < ZOOM.most / ZOOM_END}
                onOut={() => zoomBy(1 / PRESS_ZOOM)}
                onFit={() => engine.current?.fit()}
                onIn={() => zoomBy(PRESS_ZOOM)}
              />
            </div>
          </div>
          <BrainHints orbs={mode === "orbs"} />
        </div>
      )}
      {tour !== undefined && (
        <div className="pointer-events-none absolute inset-x-4 bottom-4 z-300 flex justify-center">
          <div className="pointer-events-auto">
            <TourDeck
              clock={tour}
              counts={tourCounts}
              onToggle={() => setTour((was) => (was === undefined ? was : toggleTour(was, Date.now())))}
              onScrub={(seconds) => setTour((was) => (was === undefined ? was : scrubTour(was, seconds, Date.now())))}
              onLeave={leaveTour}
            />
          </div>
        </div>
      )}
      {cinema && (
        <p className="pointer-events-none absolute inset-x-4 bottom-4 z-300 text-center font-code text-brain-caption text-faint">{BrainFootLines.leaveCinema}</p>
      )}
      {picked !== undefined && !cinema && (
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

type BrainKeyActions = {
  picked: boolean;
  touring: boolean;
  cinema: boolean;
  lit: boolean;
  close: () => void;
  leaveTour: () => void;
  leaveCinema: () => void;
  unlight: () => void;
  space: () => void;
  search: () => void;
  fit: () => void;
  center: () => void;
  replay: () => void;
  tour: () => void;
  motion: () => void;
  view: (index: number) => void;
  zoom: (factor: number) => void;
  open: () => void;
  walk: (step: number) => void;
};

/**
 * The Mac's keys over the brain, while no field has the cursor: F or 0 fits and C centers, R replays, T tours, M and
 * the space bar turn Motion, one to three pick the view, slash searches, plus and minus zoom, Return opens the mark
 * walked to and the arrows walk the marks. Escape puts away the card, then the tour, then Cinema, then the lit area.
 */
function useBrainKeys(actions: BrainKeyActions): void {
  const latest = useRef(actions);
  latest.current = actions;
  useEffect(() => {
    const press = (event: KeyboardEvent) => {
      if (typing(event.target) || pressing(event) || event.metaKey || event.ctrlKey || event.altKey) return;
      const act = latest.current;
      const handled = (): void => event.preventDefault();
      if (event.key === "Escape") {
        if (act.picked) act.close();
        else if (act.touring) act.leaveTour();
        else if (act.cinema) act.leaveCinema();
        else if (act.lit) act.unlight();
        else return;
        return handled();
      }
      if (event.key === " ") {
        act.space();
        return handled();
      }
      const key = event.key.toLowerCase();
      if (key === BRAIN_KEYS.search) act.search();
      else if (key === BRAIN_KEYS.fit.toLowerCase() || key === "0") act.fit();
      else if (key === BRAIN_KEYS.center.toLowerCase()) act.center();
      else if (key === BRAIN_KEYS.replay.toLowerCase()) act.replay();
      else if (key === BRAIN_KEYS.tour.toLowerCase()) act.tour();
      else if (key === BRAIN_KEYS.motion.toLowerCase()) act.motion();
      else if (key === "1" || key === "2" || key === "3") act.view(Number(key) - 1);
      else if (key === "+" || key === "=") act.zoom(PRESS_ZOOM);
      else if (key === "-") act.zoom(1 / PRESS_ZOOM);
      else if (event.key === "Enter") act.open();
      else if (event.key === "ArrowRight" || event.key === "ArrowDown") act.walk(1);
      else if (event.key === "ArrowLeft" || event.key === "ArrowUp") act.walk(-1);
      else return;
      handled();
    };
    window.addEventListener("keydown", press);
    return () => window.removeEventListener("keydown", press);
  }, []);
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

/** The heading over the brain's top left, the Mac's `BrainHeading`: what it is, the two line title, its counts and the page's own lines. */
function BrainHeading({ stats, foot }: { stats: { memories: number; sources: number; connections: number }; foot: ReactNode }) {
  const stat = (count: number, caption: string) => (
    <div className="flex flex-col gap-0.5">
      <span className="text-brain-numeral leading-none font-semibold tabular-nums text-foreground">{count}</span>
      <span className="font-code text-brain-caption font-medium tracking-heading text-faint">{caption}</span>
    </div>
  );
  return (
    <div className="flex max-w-(--spacing-brain-heading) flex-col gap-2">
      <p className="font-code text-brain-overline font-medium tracking-heading text-muted">{BRAIN_HEADING.overline}</p>
      <h2 className="text-brain-headline leading-tight font-semibold tracking-title">
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
