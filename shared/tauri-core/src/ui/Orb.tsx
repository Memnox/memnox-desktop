import { useEffect, useRef } from 'react';
import { OrbMotion, orbFit, type OrbState, type OrbUniforms, type Reaction } from '../core';
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

/**
 * The particle sphere, drawn with WebGL2 from the core's `OrbMotion`. Where WebGL2 is missing, as on an
 * old Linux GPU driver, the plain dot from the stylesheet stands in for it.
 */
export function Orb({ side, state, waiting, handle }: { side: number; state: OrbState; waiting: boolean; handle?: (orb: OrbHandle) => void }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const now = useRef({ state, waiting });
  now.current = { state, waiting };
  // Read through a ref, since a new callback each render must not tear the GL context down.
  const handed = useRef(handle);
  handed.current = handle;

  useEffect(() => {
    const gl = canvas.current?.getContext('webgl2', { premultipliedAlpha: true, alpha: true });
    const made = gl === null || gl === undefined ? undefined : program(gl);
    if (gl === null || gl === undefined || made === undefined) return;
    const seconds = () => performance.now() / 1000;
    const motion = new OrbMotion(seconds());
    handed.current?.({ react: (reaction) => motion.react(reaction, seconds()) });
    const scale = window.devicePixelRatio || 1;
    const fit = orbFit(side);
    const at = (name: string) => gl.getUniformLocation(made, name);
    gl.useProgram(made);
    gl.enable(gl.BLEND);
    // Additive, so dots in front of one another glow brighter rather than hide each other.
    gl.blendFunc(gl.ONE, gl.ONE);
    let frame = 0;
    const draw = () => {
      const u = motion.frame(seconds(), now.current.state, 0, now.current.waiting);
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
      frame = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(frame);
  }, [side]);

  const pixels = Math.round(side * (window.devicePixelRatio || 1));
  return <canvas ref={canvas} className="shrink-0" width={pixels} height={pixels} style={{ width: side, height: side }} aria-hidden />;
}
