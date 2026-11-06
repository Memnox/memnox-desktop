import { fitTo, ZOOM } from "../../../../core/domain/memory-arms/arms-fit";
import type { TimelineFrame } from "../../../../core/domain/memory-arms/arms-lanes";
import type { ArmsItem, ArmsModel } from "../../../../core/domain/memory-arms/arms-model";
import { approach, easeInOutCubic, OPENING, PARTICLE, springAtRest, springStep, type Spring } from "../../../../core/domain/memory-arms/arms-motion";
import { paintFrame } from "./arms-paint";
import { markUrl } from "./arms-support";
import { blend, makeDots, place, sectorOfPoint, type ArmsMode, type Dots, type View } from "../../../../core/domain/memory-arms/arms-scene";
import { brainPoint, layerOfPoint, REACH, type Projected, type Vec2 } from "../../../../core/domain/memory-arms/arms-shape";
import { ASSEMBLED, isAssembled, opened, poseAt, tourSeed, tourSeconds, type TourClock, type TourPose } from "../../../../core/domain/memory-arms/arms-tour";
import type { Pen } from "./arms-draw";

/**
 * The ARMS map's one draw loop. React hands it props and input; it keeps the
 * clocks, springs and screen positions in plain fields, so a frame allocates
 * almost nothing and thousands of dots stay one fill per colour.
 */

export type EngineProps = {
  mode: ArmsMode;
  motion: boolean;
  speed: number;
  reduced: boolean;
  sector: string | undefined;
  selected: string | undefined;
  matches: ReadonlySet<string>;
  /** Every name drawn whatever the zoom, the legend's Show all labels. */
  allLabels: boolean;
  /** The tour's clock while it runs, which poses every layer from one playhead. */
  tour: TourClock | undefined;
};

export type Particle = { item: number; app: number; start: number; trail: number[] };

/** What the pointer is over, in the stage's own pixels, for the hover card. */
export type Hovered = { item: ArmsItem; x: number; y: number; radius: number };

/** How quickly a flat view let go mid drag slows, per second, and the speed it counts as stopped at. */
const GLIDE_FRICTION = 5;
const GLIDE_REST = 0.002;
/** How much of the last pointer speed carries over each event, so the slide follows the hand rather than one jolt. */
const GLIDE_SMOOTHING = 0.6;
/** A hand held still this long before letting go means stop here, not slide. */
const GLIDE_HELD_SECONDS = 0.08;
/** An arrow key pans this share of the screen, and turns the orbs this many radians per key. */
const KEY_PAN_SHARE = 0.15;
const ORB_KEY_TURN = 0.25;
/** How lit a hovered mark's neighbours are against the mark itself. */
const NEIGHBOUR_LIGHT = 0.65;
const MORPH_SECONDS = 0.9;
/** A sync that brings hundreds sends this many travelling, which still reads as a burst. */
const MOST_ARRIVALS = 12;
/** A view change without motion is a crossfade this long rather than a morph. */
const FADE_SECONDS = 0.4;
const REDUCED_FADE_SECONDS = 0.8;
const AUTO_ORBIT = 0.16;
const ORBIT_FRICTION = 2.6;
const PITCH_MOST = 1.1;
const LIGHT_RATE = 7;
/** Dots per screen pixel of drawing, between a floor and a ceiling, so a big screen is not sparse. */
const DOTS = { fewest: 1400, most: 3600, pixelsEach: 260 } as const;
const DUST_SEED = 7;
/** Where the 3D view rests and turns back to on Center. */
const RESTING_VIEW: View = { yaw: -0.5, pitch: 0.25 };
/** Flying to a mark draws at least this close, where its name and its neighbours' are written, the Mac's `flyZoom`. */
const FLY_ZOOM = 1.6;

export class ArmsEngine {
  readonly canvas: HTMLCanvasElement;
  readonly pen: Pen;
  model: ArmsModel = { items: [], sectors: [], memories: 0, rings: { envelope: 0.2, rules: 0.29, apps: 0.53 }, empty: true };
  dots: Dots = makeDots(this.model, DOTS.fewest, DUST_SEED);
  links = new Map<string, string[]>();
  timeline: TimelineFrame = { places: new Map(), undated: [] };
  /** Each label's measured width, so a frame measures a name once rather than every time it is drawn. */
  widths = new Map<string, number>();
  /** The hovered mark's neighbours, lit with it along their spokes. */
  neighbours = new Set<number>();
  onHover: ((hovered: Hovered | undefined) => void) | undefined = undefined;
  /** Called after every painted frame, so the detail card follows its mark through pan, zoom and orbit. */
  onFrame: (() => void) | undefined = undefined;
  /** Once the person zooms or pans, a new record no longer refits the camera under them. */
  moved = false;
  index = new Map<string, number>();
  images = new Map<string, HTMLImageElement>();
  props: EngineProps = { mode: "brain", motion: true, speed: 1, reduced: false, sector: undefined, selected: undefined, matches: new Set(), allLabels: false, tour: undefined };
  /** Told whenever the zoom it is headed for changes, so the zoom buttons know when they are at an end. */
  onZoom: ((k: number) => void) | undefined = undefined;
  /** The tour's pose this frame, assembled while no tour runs. */
  pose: TourPose = ASSEMBLED;

  width = 0;
  height = 0;
  /** Idle time, which only runs while motion is on; elapsed always runs. */
  clock = 0;
  elapsed = 0;
  opening = 0;
  from: ArmsMode = "brain";
  morph = 1;
  /** The crossfade a calm view change takes instead of the morph. */
  fade = 1;
  cam = { x: { value: 0, velocity: 0 } as Spring, y: { value: 0, velocity: 0 } as Spring, k: { value: 1, velocity: 0 } as Spring };
  target = { x: 0, y: 0, k: 1 };
  view: View = { ...RESTING_VIEW };
  spin = { yaw: 0, pitch: 0 };
  dragging = false;
  hover = -1;
  lit = new Float32Array(0);
  sectorLight = new Float32Array(0);
  particles: Particle[] = [];
  sx = new Float32Array(0);
  sy = new Float32Array(0);
  sr = new Float32Array(0);

  private frame = 0;
  private last = 0;
  private hidden = false;
  /** Set once the stage lets this engine go, so a late image or event can never start a second loop on the canvas. */
  private disposed = false;
  /** A flat view let go mid drag keeps sliding, slowing to rest, in brain units per second. */
  private glide = { x: 0, y: 0 };

  constructor(canvas: HTMLCanvasElement, paint: Pen["paint"], family: string) {
    this.canvas = canvas;
    const ctx = canvas.getContext("2d");
    if (ctx === null) throw new Error("No 2D canvas here.");
    this.pen = { ctx, paint, family };
  }

  setPaint(paint: Pen["paint"]): void {
    this.pen.paint = paint;
    this.wake();
  }

  setModel(model: ArmsModel, links: Map<string, string[]>, timeline: TimelineFrame): void {
    const grew = model.items.length !== this.model.items.length;
    const hoveredId = this.model.items[this.hover]?.id;
    this.model = model;
    this.links = links;
    this.timeline = timeline;
    this.dots = makeDots(model, this.dotBudget(), DUST_SEED);
    for (const item of model.items) {
      if (item.logo !== undefined) this.preload(item.logo);
      if (item.picture !== undefined) this.preload(item.picture);
    }
    this.index = new Map(model.items.map((item, at) => [item.id, at]));
    const count = model.items.length;
    if (this.lit.length !== count) {
      this.lit = new Float32Array(count);
      this.sx = new Float32Array(count);
      this.sy = new Float32Array(count);
      this.sr = new Float32Array(count);
    }
    if (this.sectorLight.length !== model.sectors.length) this.sectorLight = new Float32Array(model.sectors.length).fill(1);
    /* The hovered mark stays hovered when the new record still holds it, so a refetch never drops the hover card. */
    const stillThere = hoveredId === undefined ? -1 : (this.index.get(hoveredId) ?? -1);
    if (stillThere >= 0) {
      /* Quietly, without telling the view, since telling it renders it and a render hands the engine a record again. */
      this.hover = stillThere;
      this.neighbours = this.neighboursOf(stillThere);
    } else if (hoveredId !== undefined) {
      this.hover = -2;
      this.setHover(-1);
    }
    /* A brain built from what exists changes size as it grows, so it is framed again until the person moves it. */
    if (grew && !this.moved) this.frameNodes(true);
    this.wake();
  }

  private dotBudget(): number {
    const wanted = Math.round((this.width * this.height) / DOTS.pixelsEach);
    return Math.max(DOTS.fewest, Math.min(DOTS.most, wanted));
  }

  /** Loads a mark or a picture once, keyed by its address, and draws again when it lands. */
  preload(src: string): void {
    if (this.images.has(src)) return;
    const image = new Image();
    image.decoding = "async";
    image.onload = () => this.wake();
    image.src = markUrl(src);
    this.images.set(src, image);
  }

  /** A loaded image by its address, or undefined while it loads or when it failed. */
  imageOf(src: string | undefined): HTMLImageElement | undefined {
    const image = src === undefined ? undefined : this.images.get(src);
    return image !== undefined && image.complete && image.naturalWidth > 0 ? image : undefined;
  }

  setProps(next: EngineProps): void {
    if (next.mode !== this.props.mode) {
      this.from = this.props.mode;
      this.morph = 0;
      this.fade = 0;
    }
    const changed = next.mode !== this.props.mode;
    this.props = next;
    if (changed) this.frameNodes(false);
    this.wake();
  }

  resize(width: number, height: number, ratio: number): void {
    this.width = width;
    this.height = height;
    this.canvas.width = Math.round(width * ratio);
    this.canvas.height = Math.round(height * ratio);
    this.pen.ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.dots = makeDots(this.model, this.dotBudget(), DUST_SEED);
    if (!this.moved) this.frameNodes(true);
    this.wake();
  }

  /** Brain units to screen pixels at zoom one, so the whole drawing fits the frame. */
  get unit(): number {
    return Math.min(this.width / (2 * REACH.x), this.height / (2 * REACH.y)) * 0.9;
  }

  /** How far the morph has run, eased, and the view each end of it stands in. */
  get eased(): number {
    return this.props.reduced ? 1 : easeInOutCubic(this.morph);
  }

  /** One point's place on screen under the current morph and camera. */
  at(theta: number, f: number, phi: number, line: Vec2): Projected {
    const view = this.turned;
    const to = place(this.props.mode, theta, f, phi, line, view);
    const p = this.morph >= 1 || this.props.reduced ? to : blend(place(this.from, theta, f, phi, line, view), to, this.eased);
    // The tour pushes in and stands back about the middle of the canvas, over wherever the camera is.
    const scale = this.unit * this.cam.k.value * (this.props.mode === "timeline" ? 1 : this.pose.zoom);
    return { x: this.width / 2 + (p.x - this.cam.x.value) * scale, y: this.height / 2 - (p.y - this.cam.y.value) * scale, scale: p.scale, depth: p.depth };
  }

  /** The 3D view with the tour's turntable on top. */
  private get turned(): View {
    return this.pose.turn === 0 ? this.view : { yaw: this.view.yaw + this.pose.turn, pitch: this.view.pitch };
  }

  /**
   * One item's place with its assembly opened by the tour, as the Mac opens the flat spot before it is projected: the
   * flat spot is opened, then read back as an angle and a share so the 3D view turns it as it turns everything else.
   */
  atItem(item: ArmsItem, index: number, line: Vec2): Projected {
    if (isAssembled(this.pose) || this.props.mode === "timeline") return this.at(item.theta, item.f, item.phi, line);
    const sector = item.layer === "memory" && item.sector !== undefined ? this.model.sectors.find((each) => each.key === item.sector) : undefined;
    const flat = opened(brainPoint(item.theta, item.f), item.layer, sector === undefined ? undefined : { x: sector.x, y: sector.y }, tourSeed(index), this.pose);
    const back = layerOfPoint(flat);
    return this.at(back.theta, back.f, item.phi, line);
  }

  /** How much of the timeline is showing, from 0 to 1, which the labels crossfade on. */
  get timelineWeight(): number {
    const e = this.morph >= 1 ? 1 : this.eased;
    const now = this.props.mode === "timeline" ? 1 : 0;
    const was = this.from === "timeline" ? 1 : 0;
    return was + (now - was) * e;
  }

  replay(): void {
    this.opening = 0;
    this.wake();
  }

  /** Fit: the camera frames the marks that exist, not the silhouette they could fill. */
  fit(): void {
    this.moved = false;
    this.frameNodes(false);
  }

  /** Center stands the 3D brain back up at its resting tilt and fits the view again, the Mac's C. */
  center(): void {
    this.view = { ...RESTING_VIEW };
    this.spin = { yaw: 0, pitch: 0 };
    this.fit();
  }

  /**
   * The arrows walk the marks in turn, the Mac's arrows: the next is hovered and the camera flies to it, close
   * enough to read its name. Answers the mark now hovered.
   */
  walk(step: number): ArmsItem | undefined {
    const count = this.model.items.length;
    if (count === 0) return undefined;
    const here = this.hover >= 0 ? this.hover : step > 0 ? -1 : 0;
    const next = (((here + step) % count) + count) % count;
    this.setHover(next);
    const item = this.model.items[next]!;
    if (this.props.mode !== "orbs") {
      this.moved = true;
      const at = this.world(item);
      this.target = { x: at.x, y: at.y, k: Math.max(this.target.k, FLY_ZOOM) };
      this.onZoom?.(this.target.k);
    }
    this.wake();
    return item;
  }

  /** Where one item stands in the current view before the camera, in brain units. */
  world(item: ArmsItem): Vec2 {
    const line = this.timeline.places.get(item.id) ?? { x: 0, y: 0 };
    const p = place(this.props.mode, item.theta, item.f, item.phi, line, this.view);
    return { x: p.x, y: p.y };
  }

  private frameNodes(snap: boolean): void {
    if (this.width === 0) return;
    this.target = fitTo(this.model.items.map((item) => this.world(item)), { width: this.width, height: this.height, unit: this.unit });
    this.onZoom?.(this.target.k);
    if (snap && this.opening === 0) {
      this.cam.x = { value: this.target.x, velocity: 0 };
      this.cam.y = { value: this.target.y, velocity: 0 };
      this.cam.k = { value: this.target.k, velocity: 0 };
    }
    this.wake();
  }

  zoomBy(factor: number, about?: Vec2): void {
    this.moved = true;
    const k = Math.min(ZOOM.most, Math.max(ZOOM.least, this.target.k * factor));
    if (about !== undefined) {
      const scale = this.unit;
      const wx = this.target.x + (about.x - this.width / 2) / (scale * this.target.k);
      const wy = this.target.y - (about.y - this.height / 2) / (scale * this.target.k);
      this.target.x = wx - (about.x - this.width / 2) / (scale * k);
      this.target.y = wy + (about.y - this.height / 2) / (scale * k);
    }
    this.target.k = k;
    this.onZoom?.(k);
    this.wake();
  }

  /** A drag: it orbits the shells in depth and pans the flat views. */
  drag(dx: number, dy: number, dt: number): void {
    if (this.props.mode === "orbs") {
      this.view.yaw += dx * 0.008;
      this.view.pitch = Math.max(-PITCH_MOST, Math.min(PITCH_MOST, this.view.pitch + dy * 0.006));
      this.spin = { yaw: (dx * 0.008) / Math.max(dt, 1 / 120), pitch: (dy * 0.006) / Math.max(dt, 1 / 120) };
    } else {
      this.moved = true;
      const scale = this.unit * this.cam.k.value;
      this.target.x -= dx / scale;
      this.target.y += dy / scale;
      this.cam.x = { value: this.target.x, velocity: 0 };
      this.cam.y = { value: this.target.y, velocity: 0 };
      /* Smoothed, so one late pointer event cannot fling the map across the screen when it is let go. */
      const step = Math.max(dt, 1 / 120);
      this.glide = {
        x: this.glide.x * GLIDE_SMOOTHING + (-dx / scale / step) * (1 - GLIDE_SMOOTHING),
        y: this.glide.y * GLIDE_SMOOTHING + (dy / scale / step) * (1 - GLIDE_SMOOTHING),
      };
    }
    this.wake();
  }

  /** A grab begins: whatever slide was under way stops under the hand. */
  grab(): void {
    this.dragging = true;
    this.glide = { x: 0, y: 0 };
    this.spin = { yaw: 0, pitch: 0 };
  }

  /** The hand let go: a flat view slides on from how fast it was moving, unless it was held still before letting go. */
  release(heldFor: number): void {
    this.dragging = false;
    if (heldFor > GLIDE_HELD_SECONDS || this.props.reduced) this.glide = { x: 0, y: 0 };
    this.wake();
  }

  /** The arrow keys pan by a share of the screen, springing there. */
  panBy(dx: number, dy: number): void {
    if (this.props.mode === "orbs") {
      this.view.yaw += dx * ORB_KEY_TURN;
      this.view.pitch = Math.max(-PITCH_MOST, Math.min(PITCH_MOST, this.view.pitch + dy * ORB_KEY_TURN));
    } else {
      this.moved = true;
      const scale = this.unit * this.target.k;
      this.target.x += (dx * this.width * KEY_PAN_SHARE) / scale;
      this.target.y -= (dy * this.height * KEY_PAN_SHARE) / scale;
    }
    this.wake();
  }

  /** What is under a screen point: an item first, else the cluster of memory that point lies in. */
  hit(x: number, y: number): { item?: ArmsItem; sector?: string } {
    let best = -1;
    let bestGap = Number.POSITIVE_INFINITY;
    for (let at = 0; at < this.model.items.length; at += 1) {
      const gap = Math.hypot(this.sx[at]! - x, this.sy[at]! - y);
      if (gap < this.sr[at]! + 5 && gap < bestGap) {
        best = at;
        bestGap = gap;
      }
    }
    const item = this.model.items[best];
    if (item !== undefined) return { item };
    if (this.props.mode !== "brain" || this.morph < 1) return {};
    const scale = this.unit * this.cam.k.value;
    const point = { x: (x - this.width / 2) / scale + this.cam.x.value, y: -(y - this.height / 2) / scale + this.cam.y.value };
    const sector = this.model.sectors[sectorOfPoint(this.model.sectors, point)];
    return sector === undefined ? {} : { sector: sector.key };
  }

  setHover(index: number): void {
    if (index === this.hover) return;
    this.hover = index;
    const item = this.model.items[index];
    this.neighbours = this.neighboursOf(index);
    this.onHover?.(item === undefined ? undefined : { item, x: this.sx[index]!, y: this.sy[index]!, radius: this.sr[index]! });
    this.wake();
  }

  private neighboursOf(index: number): Set<number> {
    const item = this.model.items[index];
    return new Set(
      (item === undefined ? [] : (this.links.get(item.id) ?? [])).map((id) => this.index.get(id)).filter((at): at is number => at !== undefined),
    );
  }

  /** New records travel in from their app; without motion they only light where they land. */
  arrive(ids: readonly string[]): void {
    for (const id of ids.slice(0, MOST_ARRIVALS)) {
      const item = this.index.get(id);
      if (item === undefined) continue;
      const sector = this.model.items[item]?.sector;
      const app = sector === undefined ? -1 : (this.index.get(`app:${sector}`) ?? -1);
      if (this.props.motion && !this.props.reduced) this.particles.push({ item, app, start: this.elapsed, trail: [] });
      else this.lit[item] = 1;
    }
    this.wake();
  }

  setHidden(hidden: boolean): void {
    this.hidden = hidden;
    if (hidden) this.stop();
    else this.wake();
  }

  wake(): void {
    if (this.disposed || this.frame !== 0 || this.hidden || this.width === 0) return;
    this.last = performance.now();
    this.frame = requestAnimationFrame(this.tick);
  }

  stop(): void {
    if (this.frame !== 0) cancelAnimationFrame(this.frame);
    this.frame = 0;
  }

  /** For good: the canvas now belongs to another engine, so this one stops and never draws on it again. */
  dispose(): void {
    this.disposed = true;
    this.stop();
    this.onHover = undefined;
    this.onFrame = undefined;
    this.onZoom = undefined;
    for (const image of this.images.values()) image.onload = null;
  }

  private tick = (now: number): void => {
    this.frame = 0;
    const dt = Math.min(0.05, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    const busy = this.advance(dt);
    paintFrame(this);
    this.onFrame?.();
    if (busy) this.frame = requestAnimationFrame(this.tick);
  };

  /** Moves every clock and spring on by one frame, and says whether anything is still moving. */
  private advance(dt: number): boolean {
    const { motion, reduced, speed, mode, selected, tour } = this.props;
    this.pose = tour === undefined || reduced ? ASSEMBLED : poseAt(tourSeconds(tour, Date.now()));
    const touring = tour !== undefined && tour.held === undefined && !reduced;
    // A picked node holds the brain still, so it and its card stay where the person clicked.
    const live = motion && !reduced && selected === undefined;
    const paced = dt * speed;
    this.elapsed += paced;
    if (live) this.clock += paced;
    const openingEnd = reduced ? REDUCED_FADE_SECONDS : OPENING.total;
    if (this.opening < openingEnd) this.opening = Math.min(openingEnd, this.opening + (reduced ? dt : paced));
    if (this.morph < 1) this.morph = Math.min(1, this.morph + (reduced ? 1 : dt / MORPH_SECONDS));
    let settling = false;
    for (const axis of ["x", "y", "k"] as const) {
      this.cam[axis] = springStep(this.cam[axis], this.target[axis], dt);
      if (!springAtRest(this.cam[axis], this.target[axis])) settling = true;
      else this.cam[axis] = { value: this.target[axis], velocity: 0 };
    }
    let sliding = false;
    if (!this.dragging && this.props.mode !== "orbs" && Math.hypot(this.glide.x, this.glide.y) > GLIDE_REST) {
      this.target.x += this.glide.x * dt;
      this.target.y += this.glide.y * dt;
      this.cam.x = { value: this.target.x, velocity: 0 };
      this.cam.y = { value: this.target.y, velocity: 0 };
      const keep = Math.exp(-GLIDE_FRICTION * dt);
      this.glide = { x: this.glide.x * keep, y: this.glide.y * keep };
      sliding = true;
    }
    let orbiting = false;
    if (mode === "orbs" && !this.dragging) {
      this.view.yaw += this.spin.yaw * dt + (live ? AUTO_ORBIT * paced : 0);
      this.view.pitch = Math.max(-PITCH_MOST, Math.min(PITCH_MOST, this.view.pitch + this.spin.pitch * dt));
      const keep = Math.exp(-ORBIT_FRICTION * dt);
      this.spin = { yaw: this.spin.yaw * keep, pitch: this.spin.pitch * keep };
      orbiting = Math.abs(this.spin.yaw) + Math.abs(this.spin.pitch) > 0.002;
    }
    const lighting = this.ease(dt);
    this.particles = this.particles.filter((each) => this.elapsed - each.start < PARTICLE.life);
    if (this.fade < 1) this.fade = Math.min(1, this.fade + dt / FADE_SECONDS);
    return touring || sliding || this.fade < 1 || live || this.opening < openingEnd || this.morph < 1 || settling || orbiting || lighting || this.particles.length > 0;
  }

  /** Eases each item's light and each sector's, and says whether any is still on its way. */
  private ease(dt: number): boolean {
    let moving = false;
    const { selected, matches, sector } = this.props;
    this.model.items.forEach((item, at) => {
      const wanted = at === this.hover || item.id === selected || matches.has(item.id) ? 1 : this.neighbours.has(at) ? NEIGHBOUR_LIGHT : 0;
      const was = this.lit[at]!;
      const next = approach(was, wanted, LIGHT_RATE, dt);
      this.lit[at] = Math.abs(next - wanted) < 0.003 ? wanted : next;
      if (this.lit[at] !== wanted) moving = true;
    });
    this.model.sectors.forEach((each, at) => {
      const wanted = sector === undefined || sector === each.key ? 1 : 0.16;
      const next = approach(this.sectorLight[at]!, wanted, LIGHT_RATE * 0.7, dt);
      this.sectorLight[at] = Math.abs(next - wanted) < 0.003 ? wanted : next;
      if (this.sectorLight[at] !== wanted) moving = true;
    });
    return moving;
  }
}
