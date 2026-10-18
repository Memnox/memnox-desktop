import {
  AppWindow,
  ArrowUpRight,
  AudioWaveform,
  BadgeCheck,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  ChevronUp,
  Circle,
  CircleArrowRight,
  CircleCheck,
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
  magnifyingglass: Search,
} as const satisfies Record<string, LucideIcon>;

export type SFSymbolName = keyof typeof SF_SYMBOLS;

/** Symbols the Mac draws filled, which lucide draws as outlines unless told to fill. */
const FILLED = new Set<SFSymbolName>(['checkmark.circle.fill', 'circle.fill', 'xmark.circle.fill']);

/** SwiftUI's symbol weights as lucide stroke widths: medium 2, semibold 2.25, bold 2.5. */
const STROKE = { regular: 1.75, medium: 2, semibold: 2.25, bold: 2.5 } as const;

export type SymbolWeight = keyof typeof STROKE;

/**
 * An SF Symbol drawn with its lucide stand in. With no size it takes 13, the body size a symbol with no
 * font of its own inherits on the Mac. A filled symbol paints its glyph in the island's black on its colour.
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
  const filled = FILLED.has(name);
  return (
    <Icon
      size={size}
      strokeWidth={STROKE[weight]}
      className={className}
      // The fill is the symbol's colour and the mark inside it the black under it, as `.fill` symbols draw.
      fill={filled ? 'currentColor' : 'none'}
      color={filled ? undefined : 'currentColor'}
      style={filled ? { stroke: '#000' } : undefined}
      aria-label={label}
      aria-hidden={label === undefined}
    />
  );
}
