import { useEffect, useRef, useState } from 'react';
import { atRest, cubicBezier, springStep, type Moving, type Spring } from '../../core';

/** How a set of values moves to its next target: on a spring, or along a timed curve. */
export type Movement = { kind: 'spring'; spring: Spring } | { kind: 'curve'; x1: number; y1: number; x2: number; y2: number; seconds: number };

/** Respect the person's wish for less motion by landing at once. */
function reducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
}

/**
 * Animates every value of `target` together toward its new numbers, as SwiftUI animates the island's
 * width, height, radius and the orb in one transaction, so they never drift apart. A spring keeps the
 * velocity it had when the target changes mid flight; a curve starts again from where it is.
 */
export function useSprings<K extends string>(target: Record<K, number>, movement: Movement): Record<K, number> {
  const [shown, setShown] = useState(target);
  const moving = useRef<Record<string, Moving>>(Object.fromEntries(Object.entries(target).map(([key, value]) => [key, { value: value as number, velocity: 0 }])));
  const key = JSON.stringify(target);

  useEffect(() => {
    const goal = JSON.parse(key) as Record<string, number>;
    if (reducedMotion()) {
      moving.current = Object.fromEntries(Object.entries(goal).map(([name, value]) => [name, { value, velocity: 0 }]));
      setShown(goal as Record<K, number>);
      return;
    }
    const from = Object.fromEntries(Object.entries(moving.current).map(([name, now]) => [name, now.value]));
    const curve = movement.kind === 'curve' ? cubicBezier(movement.x1, movement.y1, movement.x2, movement.y2) : undefined;
    let started: number | undefined;
    let last: number | undefined;
    let frame = 0;
    const step = (time: number) => {
      started ??= time;
      const seconds = last === undefined ? 0 : (time - last) / 1000;
      last = time;
      let resting = true;
      const next: Record<string, Moving> = {};
      for (const [name, value] of Object.entries(goal)) {
        const now = moving.current[name] ?? { value, velocity: 0 };
        if (movement.kind === 'spring') {
          const stepped = springStep(now, value, movement.spring, seconds);
          const done = atRest(stepped, value);
          next[name] = done ? { value, velocity: 0 } : stepped;
          resting &&= done;
        } else {
          const progress = Math.min(1, (time - started) / 1000 / movement.seconds);
          const start = from[name] ?? value;
          next[name] = { value: start + (value - start) * (curve?.(progress) ?? 1), velocity: 0 };
          resting &&= progress >= 1;
        }
      }
      moving.current = next;
      setShown(Object.fromEntries(Object.entries(next).map(([name, now]) => [name, now.value])) as Record<K, number>);
      if (!resting) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
    // The movement is read when the target changes, which is the only time it is chosen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return shown;
}
