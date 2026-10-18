import type { ReactNode } from 'react';

/**
 * `ShimmerText`: 13 medium on one line, a white band crossing words that rest at half white, once
 * every 2.2 s, for something still at work such as "Working".
 */
export function ShimmerText({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <span
      className={`animate-shimmer truncate bg-clip-text text-body font-medium text-transparent ${className ?? ''}`}
      style={{
        backgroundImage:
          'linear-gradient(90deg, rgb(255 255 255 / 0.5) 0%, rgb(255 255 255 / 0.5) 37.5%, #fff 50%, rgb(255 255 255 / 0.5) 62.5%, rgb(255 255 255 / 0.5) 100%)',
        backgroundSize: '200% 100%',
      }}
    >
      {children}
    </span>
  );
}

/** `PulseEffect` on a dot: a slow breath so the eye finds what is waiting, still under Reduce Motion. */
export function PulseDot({ colour, size = 8, className }: { colour: string; size?: number; className?: string }) {
  return (
    <span
      className={`inline-block shrink-0 animate-pulse-dot rounded-full ${className ?? ''}`}
      style={{ width: size, height: size, backgroundColor: colour }}
      aria-hidden
    />
  );
}
