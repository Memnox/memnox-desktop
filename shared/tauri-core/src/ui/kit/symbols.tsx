import {
  AppWindow,
  ArrowUpRight,
  AudioWaveform,
  BadgeCheck,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  ChevronsUpDown,
  Circle,
  CircleArrowRight,
  CircleCheck,
  CircleDashed,
  CirclePlay,
  CircleX,
  ClipboardCopy,
  Compass,
  Copy,
  CornerDownRight,
  Diff,
  Ellipsis,
  Eye,
  FileText,
  Fingerprint,
  Folder,
  GitBranch,
  Globe,
  Hand,
  History,
  Keyboard,
  Layers,
  LayoutGrid,
  Mail,
  Monitor,
  Pencil,
  Power,
  Puzzle,
  RefreshCw,
  Reply,
  Search,
  Settings,
  ShieldHalf,
  Smartphone,
  Sparkles,
  SquareArrowOutUpRight,
  SquareTerminal,
  Terminal,
  TextCursor,
  TriangleAlert,
  Undo2,
  Users,
  Volume2,
  VolumeX,
  X,
  type LucideIcon,
} from 'lucide-react';

/**
 * The Mac's SF Symbols by their own names, each to the lucide icon that stands in for it, so a screen
 * ported from Swift keeps the symbol name it was written with and every port picks the same icon.
 */
export const SF_SYMBOLS = {
  touchid: Fingerprint,
  'chevron.left': ChevronLeft,
  'chevron.backward': ChevronLeft,
  'chevron.right': ChevronRight,
  'chevron.forward': ChevronRight,
  'chevron.down': ChevronDown,
  'chevron.up': ChevronUp,
  'chevron.up.chevron.down': ChevronsUpDown,
  checkmark: Check,
  'checkmark.circle.fill': CircleCheck,
  'checkmark.seal.fill': BadgeCheck,
  circle: Circle,
  'circle.fill': Circle,
  'circle.dotted': CircleDashed,
  ellipsis: Ellipsis,
  'text.cursor': TextCursor,
  iphone: Smartphone,
  'iphone.radiowaves.left.and.right': Smartphone,
  'doc.on.doc': Copy,
  'doc.on.clipboard': ClipboardCopy,
  'doc.text': FileText,
  'arrow.up.forward.square': SquareArrowOutUpRight,
  'arrow.up.forward.app': SquareArrowOutUpRight,
  'arrow.up.forward': ArrowUpRight,
  'arrow.up.right': ArrowUpRight,
  'arrow.turn.down.right': CornerDownRight,
  'arrow.triangle.branch': GitBranch,
  'arrow.triangle.2.circlepath': RefreshCw,
  'arrow.right.circle': CircleArrowRight,
  'eye.circle.fill': Eye,
  'envelope.fill': Mail,
  'arrowshape.turn.up.left': Reply,
  xmark: X,
  'xmark.circle': CircleX,
  'xmark.circle.fill': CircleX,
  'exclamationmark.triangle.fill': TriangleAlert,
  macwindow: AppWindow,
  waveform: AudioWaveform,
  'square.stack.3d.up': Layers,
  'clock.arrow.circlepath': History,
  'square.grid.2x2': LayoutGrid,
  'shield.lefthalf.filled': ShieldHalf,
  'speaker.slash': VolumeX,
  'speaker.wave.2': Volume2,
  keyboard: Keyboard,
  gearshape: Settings,
  'hand.raised': Hand,
  pencil: Pencil,
  power: Power,
  'apple.terminal': SquareTerminal,
  terminal: Terminal,
  globe: Globe,
  puzzlepiece: Puzzle,
  'puzzlepiece.extension': Puzzle,
  safari: Compass,
  sparkles: Sparkles,
  desktopcomputer: Monitor,
  folder: Folder,
  'person.3': Users,
  'person.2': Users,
  plusminus: Diff,
  'play.circle': CirclePlay,
  'arrow.uturn.backward': Undo2,
  magnifyingglass: Search,
} as const satisfies Record<string, LucideIcon>;

export type SFSymbolName = keyof typeof SF_SYMBOLS;

/**
 * A `.fill` symbol is drawn filled: lucide's first shape is the glyph's outline (the disc, the badge, the triangle,
 * the envelope), so it takes the symbol's colour as fill and stroke, and the marks after it are cut out of it in the
 * colour of the ground under it, `--mx-symbol-ground`, as SF Symbols knocks them out.
 */
const FILLED_LOOK = '[&>*]:stroke-(--mx-symbol-ground) [&>:first-child]:stroke-current';

/** Whether the Mac draws this symbol filled. */
function filled(name: SFSymbolName): boolean {
  return name.endsWith('.fill');
}

/**
 * Filled symbols whose lucide stand in has no outline to fill, such as an eye in a disc: the disc is drawn filled
 * and the mark sits inside it in the ground's colour, at this share of the disc.
 */
const IN_DISC = new Set<SFSymbolName>(['eye.circle.fill']);
const DISC_MARK_SHARE = 0.6;

/** SwiftUI's symbol weights as lucide stroke widths: medium 2, semibold 2.25, bold 2.5. */
const STROKE = { regular: 1.75, medium: 2, semibold: 2.25, bold: 2.5 } as const;

export type SymbolWeight = keyof typeof STROKE;

/**
 * An SF Symbol drawn with its lucide stand in. With no size it takes 13, the body size a symbol with no
 * font of its own inherits on the Mac. A `.fill` symbol is filled in its colour with its marks cut out of it.
 */
export function SFSymbol({
  name,
  size = 13,
  weight = 'medium',
  className,
  label,
}: {
  name: SFSymbolName;
  size?: number;
  weight?: SymbolWeight;
  className?: string;
  /** Said by a screen reader; without it the symbol is decoration. */
  label?: string;
}) {
  const Icon = SF_SYMBOLS[name];
  const stroke = STROKE[weight];
  if (IN_DISC.has(name)) {
    return (
      <span className={`relative inline-grid shrink-0 place-items-center ${className ?? ''}`} style={{ width: size, height: size }} role={label === undefined ? undefined : 'img'} aria-label={label} aria-hidden={label === undefined}>
        <Circle size={size} strokeWidth={stroke} fill="currentColor" className="absolute inset-0" />
        <Icon size={size * DISC_MARK_SHARE} strokeWidth={stroke} className="relative stroke-(--mx-symbol-ground)" />
      </span>
    );
  }
  const solid = filled(name);
  return (
    <Icon
      size={size}
      strokeWidth={stroke}
      className={`${solid ? FILLED_LOOK : ''} ${className ?? ''}`}
      fill={solid ? 'currentColor' : 'none'}
      aria-label={label}
      aria-hidden={label === undefined}
    />
  );
}
