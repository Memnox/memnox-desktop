import { Maximize2, Minus, Plus, RotateCcw } from 'lucide-react';
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { AT_REST, fitted, zoomedAt, type Camera } from '../../../core/domain/surface-camera';
import { FORCES } from '../../../core/domain/surface-forces';
import { between, NODE_SIZE, scaleOf, ZOOM, type Placed } from '../../../core/domain/surface-geometry';
import { PANEL_WIDTH, useFollowFit, useForces, useStageSize, useSurfaceGestures } from './surface-hooks';

/**
 * A drawing somebody can move around in, the console's flat surface: nodes live in a world measured in
 * pixels and the camera decides what is on screen, so no gesture touches the layout; where things sit is
 * a settling simulation; and every line stops at the edge of what it points at. What a mark looks like
 * and what a line means belong to the drawing above this.
 */
export interface SurfaceEdge {
  readonly id: string;
  readonly from: string;
  readonly to: string;
}

export interface EdgeInk {
  readonly stroke: string;
  readonly width: number;
  readonly opacity: number;
  readonly dash?: string;
  /** A head at the end it points at, only where the claim runs one way. */
  readonly arrow?: boolean;
}

/** One wheel notch, and one press of a zoom button, out or in. */
const WHEEL_OUT = 0.92;
const WHEEL_IN = 1.08;
const PRESS_ZOOM = 1.2;
/** One press of the size buttons, a tenth either way. */
const SIZE_STEP = 0.1;
/** Past this far out a name is a smear, so it is not drawn at all. */
const NAMES_BELOW = 0.45;
/** A line to something else while one thing is followed keeps this share of its ink. */
const UNLIT_SHARE = 0.25;
/** What is not joined to the followed node stays on the picture, faintly. */
const FADED_OPACITY = 0.3;
const DEPTH_LAYERS = 100;
const SELECTED_LIFT = 200;
const ARROW_POINTS = '0,0 -7,2.8 -7,-2.8';
const HALF_TURN_DEGREES = 180;
/** A pool of light under the middle, so the surface has a near edge and a far one. */
const STAGE_GLOW = 'radial-gradient(120% 80% at 50% 42%, color-mix(in oklab, var(--color-primary) 7%, transparent), transparent 70%)';

export function SurfaceCanvas<N extends Placed, E extends SurfaceEdge>({
  label,
  nodes,
  edges,
  order,
  selected,
  onSelect,
  mark,
  inkFor,
  carries,
  legend,
}: {
  /** What the drawing is, for a screen reader. */
  label: string;
  nodes: readonly N[];
  edges: readonly E[];
  /** The order the arrow keys walk the nodes in. */
  order: readonly string[];
  selected: string | undefined;
  onSelect: (id: string | undefined) => void;
  mark: (node: N, state: { selected: boolean }) => ReactNode;
  inkFor: (edge: E, lit: boolean) => EdgeInk;
  carries?: (id: string) => readonly string[];
  legend: ReactNode;
}) {
  const stage = useRef<HTMLDivElement>(null);
  const size = useStageSize(stage);
  const [camera, setCamera] = useState<Camera>(AT_REST);
  const [nodeSize, setNodeSize] = useState(1);
  const [over, setOver] = useState<string | undefined>(undefined);
  const [held, setHeld] = useState<string | undefined>(undefined);
  const world = useForces(nodes, edges, nodeSize, FORCES, held);
  const gestures = useSurfaceGestures({ stage, size, camera, setCamera, put: world.put, setHeld });

  const placed = nodes.map((node) => {
    const spot = world.placed.get(node.id);
    return spot === undefined ? node : { ...node, x: spot.x, y: spot.y };
  });
  const at = new Map(placed.map((node) => [node.id, node] as const));
  // A wheel over the map zooms it and must not also scroll the page under it, which React's listener cannot stop.
  useEffect(() => {
    const box = stage.current;
    if (box === null) return;
    const hold = (event: WheelEvent) => event.preventDefault();
    box.addEventListener('wheel', hold, { passive: false });
    return () => box.removeEventListener('wheel', hold);
  }, []);
  const focus = selected ?? over;
  useFollowFit({ own: gestures.own, selected, placed, size, nodeSize, camera, setCamera });

  const zoomBy = (by: number, pointer: { x: number; y: number }) => {
    gestures.own.current = true;
    setCamera(zoomedAt(camera, by, pointer, size));
  };
  const middle = { x: size.width / 2, y: size.height / 2 };
  const fit = () => {
    gestures.own.current = false;
    setCamera(fitted(placed, size, nodeSize, PANEL_WIDTH));
  };

  // Arrows walk the nodes in the drawing's own order, plus and minus zoom, and zero fits it again.
  const keys = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === '+' || event.key === '=') return zoomBy(PRESS_ZOOM, middle);
    if (event.key === '-') return zoomBy(1 / PRESS_ZOOM, middle);
    if (event.key === '0') return fit();
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (step === undefined || order.length === 0) return;
    event.preventDefault();
    const here = order.indexOf(focus ?? '');
    const next = order[(here + step + order.length) % order.length];
    stage.current?.querySelector<HTMLButtonElement>(`[data-node="${CSS.escape(next ?? '')}"]`)?.focus();
  };

  return (
    <div
      ref={stage}
      role="group"
      aria-label={label}
      onKeyDown={keys}
      className={`relative h-[min(620px,70vh)] min-h-[380px] w-full touch-none overflow-hidden rounded-xl border border-panel-edge bg-card select-none ${gestures.panning ? 'cursor-grabbing' : 'cursor-grab'}`}
      style={{ backgroundImage: STAGE_GLOW }}
      onPointerDown={gestures.startPan}
      onWheel={(event) => {
        const box = stage.current?.getBoundingClientRect();
        if (box !== undefined) zoomBy(event.deltaY > 0 ? WHEEL_OUT : WHEEL_IN, { x: event.clientX - box.left, y: event.clientY - box.top });
      }}
      // Clicking the ground puts the details away, and panning across it does not.
      onClick={() => {
        if (!gestures.wasPan()) onSelect(undefined);
      }}
    >
      <div
        className="absolute top-0 left-0 origin-top-left"
        style={{ transform: `translate(${size.width / 2 - camera.x * camera.k}px, ${size.height / 2 - camera.y * camera.k}px) scale(${camera.k})` }}
      >
        <svg className="absolute top-0 left-0 overflow-visible" width={1} height={1} aria-hidden>
          {edges.map((edge) => {
            const from = at.get(edge.from);
            const to = at.get(edge.to);
            if (from === undefined || to === undefined) return null;
            const line = between(from, to, nodeSize);
            if (line === null) return null;
            const lit = focus === edge.from || focus === edge.to;
            const ink = inkFor(edge, lit);
            // Kept faint rather than removed: the lines that are not the answer say how much else there is.
            const opacity = focus !== undefined && !lit ? ink.opacity * UNLIT_SHARE : ink.opacity;
            const turn = (Math.atan2(line.y2 - line.y1, line.x2 - line.x1) * HALF_TURN_DEGREES) / Math.PI;
            return (
              <g key={edge.id}>
                <line
                  x1={line.x1}
                  y1={line.y1}
                  x2={line.x2}
                  y2={line.y2}
                  stroke={ink.stroke}
                  strokeWidth={ink.width}
                  strokeOpacity={opacity}
                  strokeLinecap="round"
                  {...(ink.dash === undefined ? {} : { strokeDasharray: ink.dash })}
                />
                {ink.arrow === true && <polygon points={ARROW_POINTS} fill={ink.stroke} fillOpacity={opacity} transform={`translate(${line.x2} ${line.y2}) rotate(${turn})`} />}
              </g>
            );
          })}
        </svg>
        {placed.map((node) => {
          const picked = selected === node.id;
          const faded = focus !== undefined && focus !== node.id && !edges.some((edge) => (edge.from === focus && edge.to === node.id) || (edge.to === focus && edge.from === node.id));
          return (
            <button
              key={node.id}
              type="button"
              data-node={node.id}
              aria-pressed={picked}
              aria-label={node.label}
              onPointerDown={(event) => {
                // The ground must not also read this as the start of a pan.
                event.stopPropagation();
                gestures.holdNode(node.id, event, at, carries?.(node.id) ?? []);
              }}
              onPointerEnter={() => setOver(node.id)}
              onPointerLeave={() => setOver(undefined)}
              onFocus={() => setOver(node.id)}
              onBlur={() => setOver(undefined)}
              onClick={(event) => {
                event.stopPropagation();
                // A drag is not a choice.
                if (!gestures.wasDrag()) onSelect(node.id);
              }}
              onDragStart={(event) => event.preventDefault()}
              style={{
                left: node.x,
                top: node.y,
                zIndex: Math.round(node.depth * DEPTH_LAYERS) + (picked ? SELECTED_LIFT : 0),
                transform: `translate(-50%, -50%) scale(${scaleOf(node.depth) * nodeSize})`,
                opacity: faded ? FADED_OPACITY : 1,
              }}
              className={`absolute rounded-xl outline-none transition-opacity select-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-card [&_svg]:pointer-events-none ${held === node.id ? 'cursor-grabbing' : 'cursor-grab'}`}
            >
              {mark(node, { selected: picked })}
              {node.captioned !== false && camera.k >= NAMES_BELOW && (
                <span className={`absolute top-full left-1/2 mt-1 line-clamp-2 w-28 -translate-x-1/2 text-center text-[10px] leading-snug font-medium ${picked ? 'text-foreground' : 'text-muted'}`}>{node.label}</span>
              )}
            </button>
          );
        })}
      </div>

      <div className="absolute top-3 left-3 flex flex-col gap-2" onPointerDown={(event) => event.stopPropagation()} onClick={(event) => event.stopPropagation()}>
        <div className="flex items-center gap-0.5 rounded-lg border border-panel-edge bg-card p-1 shadow-[0_8px_24px_rgb(0_0_0/0.1)]">
          <Control label="Fit the map" icon={Maximize2} onClick={fit} />
          <Control
            label="Arrange again"
            icon={RotateCcw}
            onClick={() => {
              gestures.own.current = false;
              world.reseed();
            }}
          />
          <span aria-hidden className="mx-0.5 h-5 w-px bg-border" />
          <Control label="Zoom out" icon={Minus} disabled={camera.k <= ZOOM.min} onClick={() => zoomBy(1 / PRESS_ZOOM, middle)} />
          <span className="w-10 text-center text-meta text-muted tabular-nums" aria-label="Zoom">{`${Math.round(camera.k * 100)}%`}</span>
          <Control label="Zoom in" icon={Plus} disabled={camera.k >= ZOOM.max} onClick={() => zoomBy(PRESS_ZOOM, middle)} />
        </div>
        <div className="flex items-center gap-0.5 rounded-lg border border-panel-edge bg-card p-1 shadow-[0_8px_24px_rgb(0_0_0/0.1)]">
          <span className="px-1.5 text-meta text-muted">Size</span>
          <Control label="Smaller marks" icon={Minus} disabled={nodeSize <= NODE_SIZE.min} onClick={() => setNodeSize(Math.max(NODE_SIZE.min, Math.round((nodeSize - SIZE_STEP) * 10) / 10))} />
          <Control label="Larger marks" icon={Plus} disabled={nodeSize >= NODE_SIZE.max} onClick={() => setNodeSize(Math.min(NODE_SIZE.max, Math.round((nodeSize + SIZE_STEP) * 10) / 10))} />
        </div>
      </div>
      <div className="absolute bottom-3 left-3 max-w-[260px]" onPointerDown={(event) => event.stopPropagation()} onClick={(event) => event.stopPropagation()}>
        {legend}
      </div>
    </div>
  );
}

function Control({ label, icon: Icon, onClick, disabled = false }: { label: string; icon: typeof Plus; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover hover:text-foreground disabled:cursor-default disabled:opacity-35 disabled:hover:bg-transparent"
    >
      <Icon size={14} aria-hidden />
    </button>
  );
}
