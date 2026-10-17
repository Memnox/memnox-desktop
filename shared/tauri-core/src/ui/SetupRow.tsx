import { useSyncExternalStore } from 'react';
import { LoaderCircle, RotateCw, TriangleAlert } from 'lucide-react';
import type { Setup } from '../core';
import { button, note } from './ui';

/** What setup is doing, or why Memnox is still not ready with one button to try again; nothing once it is ready. */
export function SetupRow({ setup }: { setup: Setup }) {
  const state = useSyncExternalStore(
    (changed) => setup.observe(changed),
    () => setup.state,
  );
  if (state.doing !== undefined) {
    return (
      <p className="flex items-center gap-2 text-xs text-muted">
        <LoaderCircle size={13} className="animate-spin" /> {state.doing}
      </p>
    );
  }
  if (state.failed === undefined) return null;
  return (
    <section className="grid gap-1.5">
      <p className={note}>
        <TriangleAlert size={13} className="mt-px shrink-0" /> {state.failed}
      </p>
      <button className={`${button('quiet')} justify-self-start`} onClick={() => void setup.ensure()}>
        <RotateCw size={14} /> Check again
      </button>
    </section>
  );
}
