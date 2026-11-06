import type { LucideIcon } from 'lucide-react';
import { forwardRef, type ButtonHTMLAttributes } from 'react';
import { PRESS_DIP } from './press';
import { Spinner } from './Spinner';

/** What a press does to the page: lead it, sit beside it, step back, cannot be undone, or read as a link. */
export type ButtonKind = 'primary' | 'secondary' | 'glass' | 'quiet' | 'danger' | 'link';

/**
 * `KitButtonFace` in the console look: 32 tall at radius 6, 13 medium, 12 inside, the icon 6 before the word; it
 * dips to 0.97 pressed and dims to 0.5 disabled, and the fill eases over Motion.quick. Keyboard focus wears the
 * console's soft ring, as a focused field does.
 */
const FRAMED_BASE =
  'inline-flex shrink-0 cursor-pointer select-none items-center justify-center gap-1.5 whitespace-nowrap rounded-control px-3 text-body-sm font-medium leading-none outline-none transition-[opacity,background-color,scale] duration-(--mx-duration-quick) ease-out enabled:active:scale-[0.97] focus-visible:ring-(length:--mx-ring-width) focus-visible:ring-(--mx-ring) disabled:cursor-default disabled:opacity-50';

/** `KitButton(kind: .glass)` keeps the Mac face even in the console: a 28 capsule, 14 inside, 13 regular in white. */
const GLASS_BASE =
  'inline-flex h-7 shrink-0 cursor-pointer select-none items-center justify-center gap-1.5 whitespace-nowrap rounded-full border border-white/[0.28] bg-white/10 px-3.5 text-body-sm text-white outline-none transition-[box-shadow,scale] duration-(--mx-duration-quick) ease-out enabled:active:scale-[0.97] enabled:hover:shadow-[inset_0_0_0_999px_rgb(255_255_255/0.08)] focus-visible:ring-(length:--mx-ring-width) focus-visible:ring-(--mx-ring) disabled:cursor-default disabled:opacity-50';

/** A quiet press has no frame until the pointer is on it, as `hoverLight` lights one: 12 medium muted. */
const QUIET_BASE = `mx-focus inline-flex shrink-0 cursor-pointer items-center justify-center gap-1 whitespace-nowrap rounded-control px-2.5 text-meta font-medium text-muted hover:bg-hover disabled:cursor-default disabled:opacity-50 ${PRESS_DIP}`;

/** `GoLink`: words in the brand blue with no frame at all, so it carries none of the button's geometry. */
const LINK_BASE = `mx-focus inline-flex w-fit cursor-pointer items-center gap-1 font-medium text-primary disabled:cursor-default disabled:opacity-50 ${PRESS_DIP}`;

const FRAMED_KIND: Record<'primary' | 'secondary' | 'danger', string> = {
  /** The solid blue dims to 0.9 under the pointer rather than changing hue. */
  primary: 'bg-primary text-white enabled:hover:opacity-90',
  /** The bordered card fill turns the hover fill; the hairline stays. */
  secondary: 'border border-control-edge bg-secondary text-foreground enabled:hover:bg-hover',
  /** `ConsoleConfirm`'s act where it takes something away. */
  danger: 'bg-destructive text-white enabled:hover:opacity-90',
};

/** 32 tall, or 26 in a dense row; a link takes no height, so its size is its words: 13, or 12 under a form. */
export type ButtonSize = 'regular' | 'small';

const BUTTON_HEIGHT: Record<ButtonSize, string> = { regular: 'h-control', small: 'h-[26px]' };
const LINK_TEXT: Record<ButtonSize, string> = { regular: 'text-body-sm', small: 'text-footnote' };

/** The button's look as classes, for an anchor or a label that must read as one. */
export function buttonClass(kind: ButtonKind = 'secondary', wide = false, size: ButtonSize = 'regular'): string {
  if (kind === 'link') return `${LINK_BASE} ${LINK_TEXT[size]}`;
  if (kind === 'glass') return `${GLASS_BASE} ${wide ? 'w-full' : ''}`;
  const base = kind === 'quiet' ? QUIET_BASE : `${FRAMED_BASE} ${FRAMED_KIND[kind]}`;
  return `${base} ${BUTTON_HEIGHT[size]} ${wide ? 'w-full' : ''}`;
}

/** The size every icon inside a button takes, so words and glyph sit on one line. */
const BUTTON_ICON = 14;

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  kind?: ButtonKind;
  /** A glyph before the words, 6 apart from them. */
  icon?: LucideIcon;
  /** A glyph after the words, as a chevron that says the press opens something. */
  trailing?: LucideIcon;
  /** The trailing glyph's size where the Mac draws it smaller than the leading one, as a micro chevron. */
  trailingSize?: number;
  /** The full width of whatever holds it. */
  wide?: boolean;
  /** Working: a spinner takes the icon's place and the press waits, so it is not sent twice. */
  busy?: boolean;
  size?: ButtonSize;
}

/** `KitButton`, in the console's shape: 32 tall at radius 6, 13 medium words, a leading icon 14, 6 before the word. */
export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { kind = 'secondary', icon: Icon, trailing: Trailing, trailingSize = BUTTON_ICON, wide = false, busy = false, size, disabled, children, className, type = 'button', ...rest },
  ref,
) {
  return (
    <button ref={ref} type={type} className={`${buttonClass(kind, wide, size)} ${className ?? ''}`} disabled={disabled === true || busy} aria-busy={busy || undefined} {...rest}>
      {busy ? <Spinner size={BUTTON_ICON} /> : Icon !== undefined && <Icon size={BUTTON_ICON} strokeWidth={2} aria-hidden />}
      {children}
      {Trailing !== undefined && <Trailing size={trailingSize} strokeWidth={2} aria-hidden />}
    </button>
  );
});

/** How big a square glyph press is: 24, 28, 32 (the Mac's `closeSide`) or 36. */
export type IconButtonSize = 'xs' | 'sm' | 'md' | 'lg';

const ICON_BUTTON_SIZE: Record<IconButtonSize, string> = { xs: 'size-6', sm: 'size-7', md: 'size-control', lg: 'size-field' };

/**
 * How far a press that cannot be used fades: `kit` is the kit's 0.5, `bar` the window's top bar, whose Back and
 * Forward fade to `AppShellView.Layout.disabledOpacity`, 0.35.
 */
export type IconButtonFade = 'kit' | 'bar';

export const ICON_BUTTON_FADE: Record<IconButtonFade, string> = { kit: 'disabled:opacity-50', bar: 'disabled:opacity-35' };

/** The glyph is footnote sized and semibold, as the Mac draws the inspector's close and pop out marks. */
const ICON_BUTTON_GLYPH = 12;
const ICON_BUTTON_STROKE = 2.5;

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  icon: LucideIcon;
  /** Said to a screen reader and shown on hover, since a glyph alone names nothing. */
  label: string;
  size?: IconButtonSize;
  /** Overrides the glyph's size where the Mac draws it larger or smaller than its footnote size. */
  iconSize?: number;
  strokeWidth?: number;
  /** How far it fades while it cannot be used. */
  fade?: IconButtonFade;
}

/** A square glyph press in muted ink that `hoverLight` lights under the pointer: the console's close, remove and more marks. */
export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { icon: Icon, label, size = 'md', iconSize = ICON_BUTTON_GLYPH, strokeWidth = ICON_BUTTON_STROKE, fade = 'kit', className, type = 'button', title, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      aria-label={label}
      title={title ?? label}
      className={`mx-focus grid ${ICON_BUTTON_SIZE[size]} shrink-0 cursor-pointer place-items-center rounded-control text-muted transition-colors duration-(--mx-duration-quick) ease-out hover:bg-hover disabled:cursor-default ${ICON_BUTTON_FADE[fade]} disabled:hover:bg-transparent ${className ?? ''}`}
      {...rest}
    >
      <Icon size={iconSize} strokeWidth={strokeWidth} aria-hidden />
    </button>
  );
});

/**
 * A surface that presses but draws itself, such as a row, a tile or a card: a button with no look of its
 * own beyond the pointing hand. Reach for `Button` or `IconButton` first; this is for what neither draws.
 */
export const Pressable = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement>>(function Pressable({ type = 'button', ...rest }, ref) {
  return <button ref={ref} type={type} {...rest} />;
});
