import type { ReactNode } from 'react';

/** Green, amber, red and grey, each always beside a word, since colour alone says nothing to many people. */
export type Tone = 'good' | 'attention' | 'bad' | 'quiet';

/** Each tone as words alone, for a number or a line in the tone's colour. */
export const TONE_TEXT: Record<Tone, string> = {
  good: 'text-success',
  attention: 'text-warm',
  bad: 'text-destructive',
  quiet: 'text-muted',
};

/** The console's pill tints: its own colour at 12 to 14 percent under the word, grey on the muted fill. */
const TONE_PILL: Record<Tone, string> = {
  good: 'text-success bg-[color-mix(in_oklab,var(--mx-success)_12%,transparent)]',
  attention: 'text-warm bg-[color-mix(in_oklab,var(--mx-warm)_14%,transparent)]',
  bad: 'text-destructive bg-[color-mix(in_oklab,var(--mx-destructive)_12%,transparent)]',
  quiet: 'text-muted bg-hover',
};

/** A state worn as the console's pill, its colour always beside the word. */
export function StatusWord({ tone, children }: { tone: Tone; children: ReactNode }) {
  return <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-meta font-medium whitespace-nowrap ${TONE_PILL[tone]}`}>{children}</span>;
}

/** A pill's edge and words: the brand blue where it marks something chosen or recommended, grey otherwise. */
export type PillTint = 'blue' | 'plain';

const PILL_TINT: Record<PillTint, string> = {
  blue: 'border-primary/40 bg-primary/10 text-primary',
  plain: 'border-border text-muted',
};

/** A small outlined pill, 11 medium, as the console's support and Recommended pills. */
export function Pill({ tint = 'plain', label, children }: { tint?: PillTint; label?: string; children: ReactNode }) {
  return (
    <span aria-label={label} className={`inline-flex shrink-0 items-center rounded-full border px-2 py-0.5 text-label font-medium whitespace-nowrap ${PILL_TINT[tint]}`}>
      {children}
    </span>
  );
}
