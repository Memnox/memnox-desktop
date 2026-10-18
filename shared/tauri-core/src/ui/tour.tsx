import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';

/**
 * The island touring its states on its own, with no daemon and nothing listening, as the Mac's
 * `--island-preview` does: `pnpm dev`, then open /previews/tour.html. Each stop is one scene of the
 * scripted preview, held for the Mac's own beat, and the tour starts again from the top when it ends.
 */

/** The island window's own size, so each scene sits where it would on the screen. */
const WINDOW = { width: 740, height: 672 } as const;
/** How long the next scene has to draw before it is swapped in, so no blank frame shows between two. */
const SWAP_AFTER_MS = 250;

/** The Mac tour's order and its seconds: sessions, one opened, the voice, an answer, a draft, a rule, a call, the history, a finish. */
export const TOUR: readonly { readonly scene: string; readonly seconds: number }[] = [
  { scene: 'peek', seconds: 3 },
  { scene: 'sessions-compact', seconds: 6 },
  { scene: 'sessions-overview', seconds: 6 },
  { scene: 'sessions-detail', seconds: 6 },
  { scene: 'voice-listening', seconds: 2.5 },
  { scene: 'conversation', seconds: 4 },
  { scene: 'answer-long', seconds: 6 },
  { scene: 'draft', seconds: 6 },
  { scene: 'voice-rule-words', seconds: 2 },
  { scene: 'rule', seconds: 6 },
  { scene: 'held', seconds: 6 },
  { scene: 'sessions-side', seconds: 6 },
  { scene: 'finished', seconds: 6.5 },
];

function Tour() {
  const [step, setStep] = useState(0);
  // Two frames, the one shown and the next drawing behind it, so a scene is never seen loading.
  const [frames, setFrames] = useState<[number, number | undefined]>([0, undefined]);
  useEffect(() => {
    const next = (step + 1) % TOUR.length;
    const load = setTimeout(() => setFrames(([shown]) => [shown, next]), (TOUR[step]?.seconds ?? 1) * 1_000 - SWAP_AFTER_MS);
    const swap = setTimeout(() => {
      setFrames([next, undefined]);
      setStep(next);
    }, (TOUR[step]?.seconds ?? 1) * 1_000);
    return () => {
      clearTimeout(load);
      clearTimeout(swap);
    };
  }, [step]);
  return (
    <div style={{ position: 'relative', width: WINDOW.width, height: WINDOW.height, margin: '0 auto' }}>
      {frames.map((index, layer) =>
        index === undefined ? null : (
          <iframe
            key={index}
            title={TOUR[index]?.scene}
            src={`/preview.html?mode=${TOUR[index]?.scene ?? 'peek'}&tour`}
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', border: 0, opacity: layer === 0 ? 1 : 0, background: 'transparent' }}
          />
        ),
      )}
    </div>
  );
}

const root = document.getElementById('root');
if (root === null) throw new Error('tour.html has no root');
createRoot(root).render(
  <StrictMode>
    <Tour />
  </StrictMode>,
);
