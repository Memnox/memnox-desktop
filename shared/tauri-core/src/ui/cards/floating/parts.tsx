import { useEffect, useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import type { CardExcerpt, CardFile } from '@memnox/core/wire';
import { extensionBadge } from '../../../core/domain/floating-cards';
import { LogoMark, SFSymbol, type SFSymbolName } from '../../kit';
import { SYSTEM_MONO } from '../MarkdownText';

/**
 * The pieces every floating card shares, from the Mac's `Cards/CardHeader.swift`, `CardControls.swift`
 * and `FileList.swift`. Unlike the island these follow the system's appearance, so they draw with the
 * adaptive tokens.
 */

/** The last two parts of a path, which is how somebody names a file out loud. */
export function shortPath(path: string): string {
  return path.split('/').filter(Boolean).slice(-2).join('/');
}

/**
 * `CardFace`: 20 padding, 440 wide, radius 16 on the surface with a 0.7 rim of ink 11% that becomes
 * 16% at 1 px under the pointer, a deep shadow, and the entrance from 0.96 at the top left.
 */
export function CardFace({ children, onHover }: { children: ReactNode; onHover?: (over: boolean) => void }) {
  const [over, setOver] = useState(false);
  return (
    <div
      className="w-[440px] origin-top-left animate-float-in rounded-island bg-surface p-5 text-foreground transition-[box-shadow] duration-[250ms] ease-out"
      style={{ boxShadow: `0 12px 60px rgb(0 0 0 / 0.5), inset 0 0 0 ${over ? 1 : 0.7}px var(${over ? '--mx-ink-edge-16' : '--mx-ink-edge-11'})` }}
      onPointerEnter={() => {
        setOver(true);
        onHover?.(true);
      }}
      onPointerLeave={() => {
        setOver(false);
        onHover?.(false);
      }}
    >
      {children}
    </div>
  );
}

/** `CardHeader`: a 28 mark, the title 22 semibold display and its subtitle 12 muted, an accessory, and Close. */
export function CardHeader({ mark, title, subtitle, accessory, onClose }: { mark?: ReactNode; title: string; subtitle?: string; accessory?: ReactNode; onClose: () => void }) {
  return (
    <div className="flex items-center gap-2.5">
      <span className="grid size-7 shrink-0 place-items-center text-ink">{mark ?? <LogoMark size={28} />}</span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="line-clamp-2 font-display text-[22px] font-semibold leading-[26px] text-foreground">{title}</span>
        {subtitle !== undefined && <span className="truncate text-footnote text-muted">{subtitle}</span>}
      </div>
      <span className="min-w-2 flex-1" />
      {accessory}
      <CloseButton onClose={onClose} />
    </div>
  );
}

/** `CloseButton`: a 26 circle, filled ink 12% only under the pointer, its cross muted then foreground; Escape presses it. */
export function CloseButton({ onClose }: { onClose: () => void }) {
  useEffect(() => {
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && onClose();
    window.addEventListener('keydown', escape);
    return () => window.removeEventListener('keydown', escape);
  }, [onClose]);
  return (
    <button
      type="button"
      className="grid size-[26px] shrink-0 cursor-pointer place-items-center rounded-full text-muted transition-[background-color,color,scale] duration-[120ms] ease-out hover:bg-[var(--mx-ink-fill-12)] hover:text-foreground active:scale-[0.94]"
      onClick={onClose}
      title="Close"
      aria-label="Close"
    >
      <SFSymbol name="xmark" size={11} weight="semibold" />
    </button>
  );
}

/**
 * `CardButton`: a capsule 14 by 8, 12.5 medium with its symbol first. Primary is near black on a light
 * window and near white on a dark one at 92%, full on hover; plain is ink 9%, 15% on hover.
 */
export function CardButton({ kind = 'plain', symbol, children, className, ...rest }: { kind?: 'primary' | 'plain'; symbol?: SFSymbolName; children: ReactNode } & ButtonHTMLAttributes<HTMLButtonElement>) {
  const look =
    kind === 'primary'
      ? 'bg-primary-fill/[0.92] text-primary-text enabled:hover:bg-primary-fill'
      : 'bg-[var(--mx-ink-fill-09)] text-ink enabled:hover:bg-[var(--mx-ink-fill-15)]';
  return (
    <button
      type="button"
      className={`inline-flex shrink-0 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 py-2 text-button font-medium transition-[background-color,scale] duration-[120ms] ease-out enabled:active:scale-[0.94] disabled:cursor-default disabled:opacity-40 ${look} ${className ?? ''}`}
      {...rest}
    >
      {symbol !== undefined && <SFSymbol name={symbol} size={12.5} />}
      {children}
    </button>
  );
}

/** A count that rolls up from 0 over 1.1 s once the card has settled, after 0.55 s. */
function useRolled(target: number): number {
  const [shown, setShown] = useState(0);
  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setShown(target);
      return;
    }
    let frame = 0;
    const begin = performance.now() + 550;
    const step = (now: number) => {
      const progress = Math.min(1, Math.max(0, (now - begin) / 1100));
      setShown(Math.round(target * (1 - (1 - progress) ** 3)));
      if (progress < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [target]);
  return shown;
}

function Count({ value, sign, tone }: { value: number; sign: string; tone: string }) {
  const shown = useRolled(value);
  return <span className={`tabular ${SYSTEM_MONO} text-[11.5px] font-medium ${tone}`}>{`${sign}${shown}`}</span>;
}

/** `FileList`: each changed file by its short path, with its lines added in green and removed in red. */
export function FileList({ files }: { files: readonly CardFile[] }) {
  if (files.length === 0) return null;
  return (
    <div className="flex flex-col gap-1 pt-0.5">
      {files.map((file) => (
        <div key={file.path} className="flex items-center gap-2">
          <span className={`min-w-0 truncate [direction:rtl] text-left ${SYSTEM_MONO} text-footnote text-foreground/90`} title={file.path}>
            {/* Cut at the head, as `.truncationMode(.head)` does, so the file's own name stays. */}
            <bdi>{shortPath(file.path)}</bdi>
          </span>
          <span className="min-w-2 flex-1" />
          {(file.added ?? 0) > 0 && <Count value={file.added ?? 0} sign="+" tone="text-success" />}
          {(file.removed ?? 0) > 0 && <Count value={file.removed ?? 0} sign={'−'} tone="text-destructive" />}
        </div>
      ))}
    </div>
  );
}

/**
 * `CodeExcerpt`: a few changed lines on the code page, radius 14, its header naming the file behind an
 * extension badge; added lines green, removed red, each with a 2 px rule in its tint.
 */
export function CodeExcerpt({ excerpt }: { excerpt: CardExcerpt }) {
  return (
    <div className="overflow-hidden rounded-[14px] border border-[var(--mx-ink-faint-05)] bg-[var(--mx-code-page)]">
      <div className="flex h-[30px] items-center gap-2 bg-white/[0.03] px-3">
        <span className={`rounded-[3px] bg-primary px-1 py-0.5 ${SYSTEM_MONO} text-[9px] font-bold leading-none text-white`}>{extensionBadge(excerpt.path)}</span>
        <span className={`truncate ${SYSTEM_MONO} text-[11.5px] font-medium text-[var(--mx-code-name)]`}>{shortPath(excerpt.path)}</span>
      </div>
      <div className="flex flex-col gap-px py-1.5">
        {excerpt.lines.map((line, index) => {
          const kind = line.startsWith('+') ? 'added' : line.startsWith('-') ? 'removed' : 'same';
          const tint = kind === 'added' ? '48 209 88' : kind === 'removed' ? '255 69 58' : '255 255 255';
          return (
            <div
              key={index}
              className={`truncate whitespace-pre px-3 py-0.5 ${SYSTEM_MONO} text-[11.5px] ${kind === 'removed' ? 'text-[var(--mx-code-removed)]' : 'text-[var(--mx-code-text)]'}`}
              style={{ backgroundColor: kind === 'same' ? undefined : `rgb(${tint} / 0.09)`, boxShadow: `inset 2px 0 0 rgb(${tint} / ${kind === 'same' ? 0.2 * 0.7 : 0.7})` }}
            >
              {line.slice(1) || ' '}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** `PageDots`: 6 dots of white 22%, the current one 16 wide in the blue. */
export function PageDots({ count, current }: { count: number; current: number }) {
  return (
    <div className="flex items-center gap-[5px]" aria-label={`Page ${current + 1} of ${count}`}>
      {Array.from({ length: count }, (_, index) => (
        <span
          key={index}
          className="h-1.5 rounded-full transition-[width,background-color] duration-[420ms] ease-[cubic-bezier(0.3,1.2,0.6,1)]"
          style={{ width: index === current ? 16 : 6, backgroundColor: index === current ? '#3b82f7' : 'rgb(255 255 255 / 0.22)' }}
        />
      ))}
    </div>
  );
}
