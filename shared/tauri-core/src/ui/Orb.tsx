import { useEffect, useRef, useState } from 'react';
import { ISLAND, OrbMotion, orbFit, type OrbState, type OrbUniforms, type Reaction } from '../core';
import { ORB_FRAGMENT, ORB_VERTEX } from './orb-shader';

/** Each single float uniform the shader declares, by the motion's name for it. */
const FLOATS: Record<string, Exclude<keyof OrbUniforms, 'ringHeights' | 'ringFades'>> = {
  uTime: 'time',
  uLevel: 'level',
  uSwirl: 'swirl',
  uHold: 'hold',
  uBurst: 'burst',
  uJitter: 'jitter',
  uDrain: 'drain',
  uPull: 'pull',
  uGlow: 'glow',
  uBounce: 'bounce',
  uKnot: 'knot',
  uSeal: 'seal',
};

/** Frames a second: every frame only while the sphere moves, since at rest it breathes too slowly to need them. */
const PACE = { resting: 20, lightMoving: 30, lightResting: 12 };
/** At or below these the orb draws fewer frames, since it competes with the agents for the same computer. */
const FEW_CORES = 4;
const SMALL_MEMORY_GB = 8;

/** A small computer by its cores, or by its memory where the web view reports it, which WebView2 does and WebKitGTK does not. */
function lightMachine(): boolean {
  const memory = 'deviceMemory' in navigator && typeof navigator.deviceMemory === 'number' ? navigator.deviceMemory : undefined;
  return navigator.hardwareConcurrency <= FEW_CORES || (memory !== undefined && memory <= SMALL_MEMORY_GB);
}

export interface OrbHandle {
  react(reaction: Reaction): void;
}

function program(gl: WebGL2RenderingContext): WebGLProgram | undefined {
  const made = gl.createProgram();
  for (const [kind, source] of [[gl.VERTEX_SHADER, ORB_VERTEX], [gl.FRAGMENT_SHADER, ORB_FRAGMENT]] as const) {
    const shader = gl.createShader(kind);
    if (shader === null) return undefined;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(made, shader);
  }
  gl.linkProgram(made);
  return gl.getProgramParameter(made, gl.LINK_STATUS) === true ? made : undefined;
}

export interface OrbProps {
  /** The orb's centre, in the box it is placed in. */
  x: number;
  y: number;
  diameter: number;
  state: OrbState;
  waiting: boolean;
  /** How loud the voice in or out is, from nothing to one, read every frame. */
  loudness?: () => number;
  handle?: (orb: OrbHandle) => void;
}

/**
 * The particle sphere, drawn with WebGL2 from the core's `OrbMotion`. One canvas for the island's whole
 * life, placed and sized as the mode moves rather than swapped, as the Mac positions one MTKView. The
 * canvas is the diameter over 0.62, leaving room for bursts and glow, and only its drawing buffer is
 * resized, so the GL context is never torn down. Where WebGL2 is missing, as on an old Linux GPU
 * driver, a soft blue dot of the same size stands in for it.
 */
export function Orb({ x, y, diameter, state, waiting, loudness, handle }: OrbProps) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const side = diameter / ISLAND.orbCanvasShare;
  const now = useRef({ state, waiting, side, loudness });
  now.current = { state, waiting, side, loudness };
  // Read through a ref, since a new callback each render must not tear the GL context down.
  const handed = useRef(handle);
  handed.current = handle;
  const [drawn, setDrawn] = useState(true);

  useEffect(() => {
    const element = canvas.current;
    const gl = element?.getContext('webgl2', { premultipliedAlpha: true, alpha: true });
    const made = gl === null || gl === undefined ? undefined : program(gl);
    if (element === null || element === undefined || gl === null || gl === undefined || made === undefined) {
      setDrawn(false);
      return;
    }
    const seconds = () => performance.now() / 1000;
    const motion = new OrbMotion(seconds());
    handed.current?.({ react: (reaction) => motion.react(reaction, seconds()) });
    const at = (name: string) => gl.getUniformLocation(made, name);
    gl.useProgram(made);
    gl.enable(gl.BLEND);
    // Additive, so dots in front of one another glow brighter rather than hide each other.
    gl.blendFunc(gl.ONE, gl.ONE);
    let frame = 0;
    let wait: ReturnType<typeof setTimeout> | undefined;
    const light = lightMachine();
    const draw = () => {
      const { state: shownState, waiting: shownWaiting, side: shownSide, loudness: level } = now.current;
      const scale = window.devicePixelRatio || 1;
      const pixels = Math.max(1, Math.round(shownSide * scale));
      if (element.width !== pixels || element.height !== pixels) {
        element.width = pixels;
        element.height = pixels;
      }
      const fit = orbFit(shownSide);
      const u = motion.frame(seconds(), shownState, level?.() ?? 0, shownWaiting);
      gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform1f(at('uCount'), fit.points);
      gl.uniform1f(at('uAspect'), 1);
      gl.uniform1f(at('uScale'), scale * fit.dot);
      for (const [uniform, key] of Object.entries(FLOATS)) gl.uniform1f(at(uniform), u[key]);
      gl.uniform4fv(at('uRingHeights'), u.ringHeights);
      gl.uniform4fv(at('uRingFades'), u.ringFades);
      gl.drawArrays(gl.POINTS, 0, fit.points);
      // A timer between frames, since an animation frame wakes the computer at the screen's rate however little it draws.
      const fps = motion.resting() ? (light ? PACE.lightResting : PACE.resting) : light ? PACE.lightMoving : undefined;
      if (fps === undefined) frame = requestAnimationFrame(draw);
      else wait = setTimeout(() => (frame = requestAnimationFrame(draw)), 1000 / fps);
    };
    draw();
    return () => {
      cancelAnimationFrame(frame);
      clearTimeout(wait);
    };
  }, []);

  const place = { left: x - side / 2, top: y - side / 2, width: side, height: side };
  return drawn ? (
    <canvas ref={canvas} className="pointer-events-none absolute" style={place} aria-hidden />
  ) : (
    <span
      className="pointer-events-none absolute rounded-full"
      style={{
        left: x - diameter / 2,
        top: y - diameter / 2,
        width: diameter,
        height: diameter,
        background: 'radial-gradient(circle at 50% 35%, #8cc8ff 0%, #1e86ee 55%, #0f47c7 100%)',
        boxShadow: '0 0 18px rgb(30 134 238 / 0.5)',
      }}
      aria-hidden
    />
  );
}
