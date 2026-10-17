/** The island's few shared looks, as Tailwind classes, so every button and note reads the same. */
const BUTTON = {
  primary: 'border-ink bg-ink font-semibold text-ground hover:bg-ink/90',
  quiet: 'border-line text-ink hover:bg-white/5',
  icon: 'border-transparent px-1.5 text-muted hover:text-ink',
} as const;

export function button(kind: keyof typeof BUTTON): string {
  return `inline-flex items-center justify-center gap-1.5 rounded-xl border px-2.5 py-2 cursor-pointer transition-colors disabled:cursor-default disabled:opacity-40 ${BUTTON[kind]}`;
}

/** A line under a card saying why a press did not go through, or what to check. */
export const note = 'flex items-start gap-1.5 text-xs text-deny';
