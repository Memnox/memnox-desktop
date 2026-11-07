import { CircleAlert, RotateCw, TriangleAlert, X } from 'lucide-react';
import type { ReactNode } from 'react';
import { KitLines } from '../../core/domain/kit-lines';
import { Pressable } from './Button';

/**
 * What a press came to, said in a line on the card fill above the page: `regular` for a page's note, `roomy` where it
 * stands as wide as the cards under it.
 */
export function Note({ roomy = false, className, children }: { roomy?: boolean; className?: string; children: ReactNode }) {
  return (
    <p role="status" className={`border border-panel-edge bg-card text-footnote text-foreground ${roomy ? 'rounded-xl px-4 py-3' : 'rounded-lg px-3.5 py-2.5'} ${className ?? ''}`}>
      {children}
    </p>
  );
}

/** What went wrong with a form, in red under it. */
export function ErrorLine({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="text-footnote text-destructive">
      {children}
    </p>
  );
}

/** The banner's warning glyph and its close mark, small beside 12 point words. */
const BANNER_ICON = 14;
const BANNER_CLOSE = 11;

/**
 * Something that did not work, inline where it happened, in the warm colour: a title over the words, and a close
 * mark where it can be put away so it never stands over the page.
 */
export function Banner({ title, words, dismiss, dismissLabel }: { title: string; words: ReactNode; dismiss?: () => void; dismissLabel?: string }) {
  return (
    <div role="status" className="flex items-start gap-2 rounded-md border border-warm/35 bg-warm/[0.08] p-3">
      <CircleAlert size={BANNER_ICON} className="mt-0.5 shrink-0 text-warm" aria-hidden />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-meta font-semibold text-foreground">{title}</span>
        <span className="text-meta break-words text-muted select-text">{words}</span>
      </div>
      {dismiss !== undefined && (
        <Pressable aria-label={dismissLabel} onClick={dismiss} className="mx-focus cursor-pointer text-muted hover:text-foreground">
          <X size={BANNER_CLOSE} strokeWidth={2.5} />
        </Pressable>
      )}
    </div>
  );
}

/** `ReadFailed`'s triangle is callout sized, as is the retry arrow in its 36 tall button. */
const FAILED_ICON = 14;
const FAILED_RETRY = 14;

/** `ReadFailed`: a read that failed is said, never drawn as an empty page, on the red wash at 5% under a 30% edge. */
export function ReadFailed({ what, retry }: { what: string; retry: () => void }) {
  return (
    <div role="alert" className="flex flex-wrap items-center gap-3 rounded-card border border-destructive/30 bg-destructive/5 p-4 text-body-sm">
      <TriangleAlert size={FAILED_ICON} className="shrink-0 text-destructive" aria-hidden />
      <p className="min-w-0 flex-1 font-medium text-foreground">{KitLines.readFailed(what)}</p>
      <Pressable className="mx-focus inline-flex h-field cursor-pointer items-center gap-2 rounded-control border border-panel-edge bg-background px-3.5 font-medium text-foreground hover:bg-hover" onClick={retry}>
        <RotateCw size={FAILED_RETRY} aria-hidden />
        {KitLines.tryAgain}
      </Pressable>
    </div>
  );
}

