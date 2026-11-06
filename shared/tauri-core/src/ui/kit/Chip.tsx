import type { ReactNode } from 'react';
import { Pressable } from './Button';
import { PRESS_DIP } from './press';

/**
 * How a chip says it is chosen to a screen reader: as the selected tab of a filter, as a pressed toggle, or as the
 * checked one of a radio group.
 */
export type ChipRole = 'tab' | 'toggle' | 'radio';

/**
 * `FilterChip` in the console look: 32 tall at radius 6, 12 inside, 13 medium when chosen and regular otherwise, its
 * count 12 medium muted 6 after; the chosen one washed in the blue at 7% under a 45% edge, the rest on the card
 * fill that lights under the pointer. It dips as it is pressed.
 */
export function Chip({ on, pick, role = 'tab', count, children }: { on: boolean; pick: () => void; role?: ChipRole; count?: number; children: ReactNode }) {
  const state = role === 'toggle' ? { 'aria-pressed': on } : role === 'tab' ? { role: 'tab', 'aria-selected': on } : { role: 'radio', 'aria-checked': on };
  return (
    <Pressable
      {...state}
      onClick={pick}
      className={`mx-focus inline-flex h-control cursor-pointer items-center gap-1.5 rounded-control border px-3 text-body-sm ${PRESS_DIP} ${on ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover'}`}
    >
      {children}
      {count !== undefined && count > 0 && <span className="text-meta font-medium tabular-nums text-muted">{count}</span>}
    </Pressable>
  );
}

/** Chips in a wrapping row 6 apart, named for what they choose between. */
export function ChipGroup({ label, role = 'tablist', className, children }: { label: string; role?: 'tablist' | 'group' | 'radiogroup'; className?: string; children: ReactNode }) {
  return (
    <div role={role} aria-label={label} className={`flex flex-wrap items-center gap-1.5 ${className ?? ''}`}>
      {children}
    </div>
  );
}
