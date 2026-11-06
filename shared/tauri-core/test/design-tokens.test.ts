import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import * as menuPanel from '../src/core/domain/menu-panel';
import * as pageMetrics from '../src/ui/app/page-metrics';
import { ICON_BUTTON_FADE } from '../src/ui/kit/Button';
import { SPACING } from '../src/ui/kit/metrics';
import * as scanLayout from '../src/ui/scan/scan-layout';
import * as sessionMetrics from '../src/ui/sessions/session-metrics';

/**
 * The Mac's design system is the source of every value this app draws with, so this reads both files and fails on
 * any token that drifted: the palettes in each appearance, the console's shapes and heights, and the scales.
 */
const swift = readFileSync(new URL('../../../macos/Sources/MemnoxVoice/Presentation/DesignSystem.swift', import.meta.url), 'utf8');
const css = readFileSync(new URL('../src/ui/styles.css', import.meta.url), 'utf8');

type Rgba = readonly [number, number, number, number];
type Appearance = 'light' | 'dark';

/** One enum's body, from its opening line to the brace that closes it. */
function swiftEnum(name: string, from = swift): string {
  const start = from.indexOf(`enum ${name} {`);
  if (start < 0) throw new Error(`DesignSystem.swift has no enum ${name}`);
  let depth = 0;
  for (let at = from.indexOf('{', start); at < from.length; at += 1) {
    if (from[at] === '{') depth += 1;
    if (from[at] === '}') depth -= 1;
    if (depth === 0) return from.slice(start, at + 1);
  }
  throw new Error(`enum ${name} never closes`);
}

/** The enum's own lines, without the enums nested in it. */
function ownLines(body: string): string {
  let depth = 0;
  return body
    .split('\n')
    .filter((line) => {
      const opens = (line.match(/\{/g) ?? []).length;
      const closes = (line.match(/\}/g) ?? []).length;
      const own = depth === 1;
      depth += opens - closes;
      return own;
    })
    .join('\n');
}

function hex(value: string): Rgba {
  const n = Number.parseInt(value.replace(/^(0x|#)/, ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1];
}

/** Each colour of a Swift palette in one appearance, aliases followed, as RGBA. */
function swiftColours(body: string, appearance: Appearance): Map<string, Rgba> {
  const colours = new Map<string, Rgba>();
  for (const [, name = '', value = ''] of ownLines(body).matchAll(/static let (\w+) = (.+)$/gm)) {
    const pair = /Color\(light: (0x\w+), dark: (0x\w+)\)/.exec(value);
    const one = /Color\(hex: (0x\w+)\)/.exec(value);
    const alpha = /Color\(darkWhite: ([\d.]+), lightBlack: ([\d.]+)\)/.exec(value);
    if (pair !== null) colours.set(name, hex((appearance === 'light' ? pair[1] : pair[2]) ?? ''));
    else if (one !== null) colours.set(name, hex(one[1] ?? ''));
    else if (alpha !== null) colours.set(name, appearance === 'light' ? [0, 0, 0, Number(alpha[2])] : [255, 255, 255, Number(alpha[1])]);
    else if (/^\w+$/.test(value.trim()) && colours.has(value.trim())) colours.set(name, colours.get(value.trim()) as Rgba);
  }
  return colours;
}

/** The declarations of the first CSS rule with this exact selector. */
function cssBlock(selector: string): Map<string, string> {
  const start = css.indexOf(`${selector} {`);
  if (start < 0) throw new Error(`styles.css has no ${selector}`);
  const body = css.slice(css.indexOf('{', start) + 1, css.indexOf('\n}', start));
  return new Map([...body.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(([, name, value]) => [name as string, (value as string).trim()]));
}

function cssColour(value: string): Rgba {
  if (value.startsWith('#')) return hex(value);
  const rgb = /rgb\((\d+) (\d+) (\d+)(?: \/ ([\d.]+))?\)/.exec(value);
  if (rgb === null) throw new Error(`not a colour: ${value}`);
  return [Number(rgb[1]), Number(rgb[2]), Number(rgb[3]), rgb[4] === undefined ? 1 : Number(rgb[4])];
}

const kebab = (name: string) => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);

/** The Swift colours whose CSS twin is a Tailwind colour rather than an adaptive `--mx-*` one. */
const THEME_COLOURS = new Set(['primary', 'deep']);

/** Colours the Mac builds from an appearance at run time, checked by hand rather than parsed. */
const COMPUTED = new Set(['ring', 'switchKnob']);

/** Compares each colour both files hold and returns how many, so a parse that found nothing cannot pass. */
function comparePalette(swiftName: string, light: Map<string, string>, dark: Map<string, string>): number {
  const body = swiftEnum(swiftName);
  let compared = 0;
  for (const [appearance, block] of [['light', light], ['dark', dark]] as const) {
    for (const [name, colour] of swiftColours(body, appearance)) {
      if (COMPUTED.has(name)) continue;
      const token = THEME_COLOURS.has(name) ? `--color-${kebab(name)}` : `--mx-${kebab(name)}`;
      const value = block.get(token) ?? light.get(token);
      if (value === undefined) continue;
      expect([appearance, token, cssColour(value)]).toEqual([appearance, token, colour]);
      compared += 1;
    }
  }
  return compared;
}

/** Each palette has more than twenty colours in each appearance. */
const LEAST_COMPARED = 40;

function swiftNumber(body: string, name: string): number {
  const found = new RegExp(`static let ${name}(?:: \\w+)? = ([\\d.]+)`).exec(body);
  if (found === null) throw new Error(`no ${name}`);
  return Number(found[1]);
}

function cssPixels(block: Map<string, string>, token: string): number {
  const value = block.get(token);
  if (value === undefined) throw new Error(`styles.css has no ${token}`);
  return Number.parseFloat(value);
}

describe('the design tokens', () => {
  it('paint the Memnox window in the console palette of the Mac', () => {
    expect(comparePalette('Console', cssBlock('html.mx-window'), cssBlock('html.mx-window[data-theme="dark"]'))).toBeGreaterThan(LEAST_COMPARED);
  });

  it('paint every other window in the Mac palette', () => {
    expect(comparePalette('Palette', cssBlock(':root'), cssBlock('[data-theme="dark"]'))).toBeGreaterThan(LEAST_COMPARED);
  });

  it('give the console its two shapes, its control heights and its ring', () => {
    const console = swiftEnum('Console');
    const window = cssBlock('html.mx-window');
    const theme = cssBlock('@theme');
    expect(cssPixels(window, '--radius-control')).toBe(swiftNumber(console, 'controlRadius'));
    expect(cssPixels(window, '--radius-card')).toBe(swiftNumber(console, 'cardRadius'));
    expect(cssPixels(theme, '--spacing-control')).toBe(swiftNumber(console, 'controlHeight'));
    expect(cssPixels(theme, '--spacing-field')).toBe(swiftNumber(console, 'fieldHeight'));
    expect(cssPixels(cssBlock(':root'), '--mx-ring-width')).toBe(swiftNumber(console, 'ringWidth'));
  });

  it('size the console type as the Mac does', () => {
    const sizes = swiftEnum('TextSize', swiftEnum('Console'));
    const theme = cssBlock('@theme');
    expect(cssPixels(theme, '--text-label')).toBe(swiftNumber(sizes, 'label'));
    expect(cssPixels(theme, '--text-meta')).toBe(swiftNumber(sizes, 'meta'));
    expect(cssPixels(theme, '--text-body-sm')).toBe(swiftNumber(sizes, 'bodySmall'));
  });

  it('keep the Mac type scale, spacing, strokes and timing', () => {
    const outside = swift.slice(swift.indexOf('static let radius'));
    const sizes = swiftEnum('TextSize', outside);
    const theme = cssBlock('@theme');
    for (const name of ['micro', 'caption', 'footnote', 'body', 'callout', 'headline', 'title']) {
      expect([name, cssPixels(theme, `--text-${name}`)]).toEqual([name, swiftNumber(sizes, name)]);
    }
    const root = cssBlock(':root');
    const spacing = swiftEnum('Spacing');
    const space: Record<string, string> = { xxSmall: 'xxs', xSmall: 'xs', small: 'sm', medium: 'md', regular: 'rg', large: 'lg', xLarge: 'xl', xxLarge: 'xxl' };
    for (const [name, short] of Object.entries(space)) expect([name, cssPixels(root, `--mx-space-${short}`)]).toEqual([name, swiftNumber(spacing, name)]);
    const stroke = swiftEnum('Stroke');
    expect(cssPixels(root, '--mx-stroke-hairline')).toBe(swiftNumber(stroke, 'hairline'));
    expect(cssPixels(root, '--mx-stroke-emphasis')).toBe(swiftNumber(stroke, 'emphasis'));
    const motion = swiftEnum('Motion');
    for (const name of ['quick', 'standard', 'slow']) expect([name, cssPixels(root, `--mx-duration-${name}`) / 1000]).toEqual([name, swiftNumber(motion, name)]);
    expect(cssPixels(theme, '--radius-key')).toBe(swiftNumber(swift, 'keycapRadius'));
  });
});

/** Every Swift source a page token is held to, under the Mac's Presentation folder, read once. */
const presentation = new URL('../../../macos/Sources/MemnoxVoice/Presentation/', import.meta.url);
const sources = new Map<string, string>();
function swiftFile(file: string): string {
  const known = sources.get(file);
  if (known !== undefined) return known;
  const read = readFileSync(new URL(file, presentation), 'utf8');
  sources.set(file, read);
  return read;
}

/**
 * One page token held to its Swift twin. `pattern` matches the Swift value with one capture, exactly once in `file`;
 * `part` picks which item of the CSS value it is, counting each number and each hex colour in order once every
 * `var(...)` is set aside, so a sum such as `calc(235px + 8px)` holds each term to its own constant. `scale` is how
 * much larger the CSS item is, as a CSS blur is twice SwiftUI's shadow radius; `nth` reads a later declaration of the
 * token, such as its dark value.
 */
interface MacMetric {
  readonly token: string;
  readonly file: string;
  readonly pattern: string;
  readonly part?: number;
  readonly scale?: number;
  readonly nth?: number;
}

const MAC_METRICS: readonly MacMetric[] = [
  // The Memnox window's frame and sidebar.
  { token: "--container-shell-page", file: "App/ShellKit.swift", pattern: "static let pageWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-side", file: "App/ShellKit.swift", pattern: "static let pagePadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-side-wide", file: "App/ShellKit.swift", pattern: "static let widePadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-side-compact", file: "App/ShellKit.swift", pattern: "static let compactPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-top", file: "App/ShellKit.swift", pattern: "static let pageTop: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-foot", file: "App/ShellKit.swift", pattern: "static let pageBottom: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-section", file: "App/ShellKit.swift", pattern: "static let sectionSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-dot", file: "App/ShellKit.swift", pattern: "static let dot: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-bar", file: "App/ShellKit.swift", pattern: "static let barHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-top-bar", file: "App/ShellKit.swift", pattern: "static let barHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-top-bar", file: "App/AppShellView.swift", pattern: "static let panelInset: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-shell-panel-inset", file: "App/AppShellView.swift", pattern: "static let panelInset: CGFloat = ([\\d.]+)" },
  { token: "--spacing-shell-badge-y", file: "App/AppShellView.swift", pattern: "static let vertical: CGFloat = ([\\d.]+)" },
  { token: "--spacing-sidebar", file: "App/AppSidebar.swift", pattern: "static let width: CGFloat = ([\\d.]+)\\s+static let railWidth" },
  { token: "--spacing-sidebar-rail", file: "App/AppSidebar.swift", pattern: "static let railWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-sidebar-row", file: "App/AppSidebar.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)\\s+static let railRow" },
  { token: "--spacing-sidebar-rail-row", file: "App/AppSidebar.swift", pattern: "static let railRow: CGFloat = ([\\d.]+)" },
  { token: "--spacing-sidebar-icon", file: "App/AppSidebar.swift", pattern: "static let iconWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-sidebar-heading", file: "App/AppSidebar.swift", pattern: "static let headingHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-sidebar-search", file: "App/AppSidebar.swift", pattern: "static let searchHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-switcher", file: "App/AppSidebar.swift", pattern: "static let width: CGFloat = ([\\d.]+)\\s+static let listHeight" },
  { token: "--spacing-switcher-list", file: "App/AppSidebar.swift", pattern: "static let listHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-switcher-row", file: "App/AppSidebar.swift", pattern: "static let listHeight: CGFloat = [\\d.]+\\s+static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--container-island", file: "Island/IslandLayout.swift", pattern: "static let width: CGFloat = ([\\d.]+)\\n\\s+/// The concave curve" },
  { token: "--spacing-island-count-trailing", file: "Island/IslandView.swift", pattern: "static let countTrailing: CGFloat = ([\\d.]+)" },
  { token: "--mx-shell-sub-nav-columns", file: "App/SubNav.swift", pattern: "static let treeWidth: CGFloat = ([\\d.]+)" },
  { token: "--mx-shell-catalog-columns", file: "Components/CategoryRail.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { token: "--shadow-lift", file: "DesignSystem.swift", pattern: "static let liftDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-lift", file: "DesignSystem.swift", pattern: "static let liftRadius: CGFloat = ([\\d.]+)", part: 2, scale: 2 },
  { token: "--shadow-lift", file: "DesignSystem.swift", pattern: "static let liftShadow = ([\\d.]+)", part: 6 },
  // The Memnox window's pages, the island's tool page and the voice words.
  { token: "--shadow-lift", file: "DesignSystem.swift", pattern: "static let liftDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-lift", file: "DesignSystem.swift", pattern: "static let liftShadow = ([\\d.]+)", part: 6 },
  { token: "--spacing-app-code-copy", file: "Components/CodeBlock.swift", pattern: "static let copyHeight: CGFloat = ([\\d.]+)" },
  { token: "--container-app-variable-name", file: "App/AddServerSheet.swift", pattern: "static let variableName: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-layer-badge", file: "App/MemoryLayersPage.swift", pattern: "static let badge: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-memory-search", file: "App/MemoryDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { token: "--container-app-skill-search", file: "App/SkillsDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-effect-band", file: "App/PoliciesDestination.swift", pattern: "static let height: CGFloat = ([\\d.]+)" },
  { token: "--shadow-app-changes", file: "DesignSystem.swift", pattern: "static let xSmall: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-app-changes", file: "Components/CategoryRail.swift", pattern: "private static let shadow = ([\\d.]+)", part: 6 },
  { token: "--container-app-description", file: "App/ProjectPages.swift", pattern: "static let descriptionWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-rule-chip", file: "App/RuleDialogParts.swift", pattern: "static let height: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-work-head", file: "App/WorkTable.swift", pattern: "static let headHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-app-choice-key", file: "App/TodayDestination.swift", pattern: "private static let keySide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tool-left", file: "Island/IslandToolPage.swift", pattern: "static let leftWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tool-mark-row", file: "Island/IslandToolPage.swift", pattern: "static let markSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tool-mark-row", file: "DesignSystem.swift", pattern: "static let medium: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-tool-halo", file: "Island/IslandToolPage.swift", pattern: "static let haloSide: CGFloat = ([\\d.]+)" },
  { token: "--blur-tool-halo", file: "Island/IslandToolPage.swift", pattern: "static let haloBlur: CGFloat = ([\\d.]+)" },
  { token: "--drop-shadow-tool-mark", file: "Island/IslandToolPage.swift", pattern: "static let markShadowDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--drop-shadow-tool-mark", file: "Island/IslandToolPage.swift", pattern: "static let markShadowRadius: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--drop-shadow-tool-mark", file: "Island/IslandToolPage.swift", pattern: "static let markShadow = ([\\d.]+)", part: 6 },
  { token: "--tracking-tool-label", file: "Island/IslandToolPage.swift", pattern: "static let labelTracking: CGFloat = ([\\d.]+)" },
  { token: "--radius-tool-ask", file: "Island/IslandToolPage.swift", pattern: "static let askRadius: CGFloat = ([\\d.]+)" },
  { token: "--color-tool-rim", file: "Island/IslandLauncher.swift", pattern: "static let tileRim = ([\\d.]+)", part: 3 },
  { token: "--mx-app-nav-groups", file: "App/SubNav.swift", pattern: "static let stackedGroup: CGFloat = ([\\d.]+)" },
  { token: "--mx-app-skill-loss-indent", file: "App/SkillsDestination.swift", pattern: "static let smallLogo: CGFloat = ([\\d.]+)" },
  { token: "--mx-app-work-columns", file: "App/WorkTable.swift", pattern: "static let numberWidth: CGFloat = ([\\d.]+)" },
  { token: "--mx-app-work-columns", file: "App/WorkTable.swift", pattern: "static let fromWidth: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--mx-app-work-columns", file: "App/WorkTable.swift", pattern: "static let whenWidth: CGFloat = ([\\d.]+)", part: 4 },
  { token: "--mx-app-work-columns", file: "App/WorkTable.swift", pattern: "static let stateWidth: CGFloat = ([\\d.]+)", part: 5 },
  { token: "--mx-app-arms-detail-most", file: "App/MemoryMapView.swift", pattern: "static let detailMost: CGFloat = ([\\d.]+)" },
  { token: "--mx-app-arms-card-most", file: "../../MemnoxVoiceCore/Domain/Memory/BrainCard.swift", pattern: "public static let margin = ([\\d.]+)", part: 2 },
  // The session windows, the island's session screens and the side panel.
  { token: "--spacing-session-close", file: "Cards/CardControls.swift", pattern: "static let target: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-keycap", file: "DesignSystem.swift", pattern: "private static let minimumWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-keycap", file: "DesignSystem.swift", pattern: "minimumWidth: CGFloat = [\\d.]+\\n\\s+private static let height: CGFloat = ([\\d.]+)" },
  { token: "--text-session-card-title", file: "Cards/CardHeader.swift", pattern: "static let titleSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-section-title", file: "LiveSession.swift", pattern: "static let titleSpacing: CGFloat = ([\\d.]+)" },
  { token: "--tracking-session-label", file: "LiveSession.swift", pattern: "static let titleTracking: CGFloat = ([\\d.]+)" },
  { token: "--tracking-session-label", file: "LiveSessionParts.swift", pattern: "static let labelTracking: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-command", file: "Components/HeldStrip.swift", pattern: "static let commandRadius: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-command", file: "LiveSessionParts.swift", pattern: "static let rowHeight: CGFloat = 17\\n\\s+static let radius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-dot", file: "Switcher.swift", pattern: "static let dotSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-dot", file: "Cards/SessionPopupView.swift", pattern: "private static let dot: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-dot", file: "LiveSession.swift", pattern: "static let dotSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-dot", file: "Side/SideView.swift", pattern: "static let dotSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-tile-width", file: "Switcher.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-tile-height", file: "Switcher.swift", pattern: "static let height: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-tile-pad", file: "Switcher.swift", pattern: "static let padding: CGFloat = ([\\d.]+)" },
  { token: "--text-session-tile-name", file: "Switcher.swift", pattern: "static let nameSize: CGFloat = ([\\d.]+)" },
  { token: "--shadow-session-tile", file: "Switcher.swift", pattern: "static let shadowDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-session-tile", file: "Switcher.swift", pattern: "static let shadowRadius: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--shadow-session-tile", file: "Switcher.swift", pattern: "static let shadowOpacity = ([\\d.]+)", part: 7 },
  { token: "--shadow-session-tile-front", file: "Switcher.swift", pattern: "static let frontShadowRadius: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--radius-session-card", file: "Cards/CardView.swift", pattern: "static let radius: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-card", file: "LiveSession.swift", pattern: "static let cornerRadius: CGFloat = ([\\d.]+)" },
  { token: "--shadow-session-card", file: "Cards/CardView.swift", pattern: "static let shadowDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-session-card", file: "Cards/CardView.swift", pattern: "static let shadowRadius: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--shadow-session-card", file: "Cards/CardView.swift", pattern: "static let shadowOpacity = ([\\d.]+)", part: 7 },
  { token: "--spacing-session-live-pad", file: "LiveSession.swift", pattern: "static let sectionSpacing: CGFloat = [\\d.]+\\n\\s+static let padding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-status-edge", file: "LiveSession.swift", pattern: "static let statusEdge: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-pill-x", file: "LiveSession.swift", pattern: "\\n\\s+static let horizontalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-pill-y", file: "LiveSession.swift", pattern: "\\n\\s+static let verticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-now-y", file: "LiveSession.swift", pattern: "private static let verticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-step", file: "LiveSession.swift", pattern: "private static let rowSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-bubble-indent", file: "LiveSession.swift", pattern: "static let personIndent: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-bubble-x", file: "LiveSession.swift", pattern: "static let bubbleHorizontalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-bubble-y", file: "LiveSession.swift", pattern: "static let bubbleVerticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--text-session-code", file: "Cards/FileList.swift", pattern: "private let codeTextSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-tab-bar", file: "LiveSessionParts.swift", pattern: "static let height: CGFloat = ([\\d.]+)\\n\\s+static let inset" },
  { token: "--spacing-session-tab-inset", file: "LiveSessionParts.swift", pattern: "static let inset: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-bubble", file: "LiveSessionParts.swift", pattern: "static let bubbleRadius: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-file-row", file: "LiveSessionParts.swift", pattern: "static let rowRadius: CGFloat = ([\\d.]+)" },
  { token: "--max-height-session-diff", file: "LiveSessionParts.swift", pattern: "static let maxHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-diff-row", file: "LiveSessionParts.swift", pattern: "static let gutter: CGFloat = [\\d.]+\\n\\s+static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-diff-gutter", file: "LiveSessionParts.swift", pattern: "static let gutter: CGFloat = ([\\d.]+)" },
  { token: "--leading-session-reply", file: "LiveSessionParts.swift", pattern: "static let blockSpacing: CGFloat = [\\d.]+\\n\\s+static let lineSpacing: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-session-focus-card", file: "Island/IslandOverview.swift", pattern: "static let focusCardWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-focus-text", file: "Island/IslandOverview.swift", pattern: "static let focusTextLeading: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-title-dot", file: "Island/IslandOverview.swift", pattern: "static let titleDotSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-subtitle-indent", file: "Island/IslandOverview.swift", pattern: "static let focusLogoSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-subtitle-indent", file: "Island/IslandOverview.swift", pattern: "static let titleDotSpacing: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-session-roll", file: "Island/IslandOverview.swift", pattern: "static let rollHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-roll-line", file: "Island/IslandOverview.swift", pattern: "static let lineHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-roll-icon", file: "Island/IslandOverview.swift", pattern: "static let iconSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-row", file: "Island/IslandOverview.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--radius-session-row", file: "Island/IslandOverview.swift", pattern: "static let rowRadius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-detail-card", file: "Island/IslandSessionDetail.swift", pattern: "static let cardWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-detail-header", file: "Island/IslandSessionDetail.swift", pattern: "static let headerSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-open", file: "Island/IslandSessionDetail.swift", pattern: "static let openSide: CGFloat = ([\\d.]+)" },
  { token: "--tracking-session-detail-label", file: "Island/IslandSessionDetail.swift", pattern: "static let labelTracking: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-detail-step", file: "Island/IslandSessionDetail.swift", pattern: "static let stepSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-files-row", file: "Island/IslandSessionDetail.swift", pattern: "static let rowSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-tile-symbol", file: "Island/IslandLauncher.swift", pattern: "static let tileSymbolFrame: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-choice-number", file: "Island/IslandQuestion.swift", pattern: "static let numberSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-side-row-y", file: "Side/SideView.swift", pattern: "static let vertical: CGFloat = ([\\d.]+)" },
  { token: "--spacing-session-side-mark", file: "Side/SideView.swift", pattern: "static let markSide: CGFloat = ([\\d.]+)\\n\\s+static let dotSide" },
  { token: "--spacing-session-keycap-gap", file: "Side/SideView.swift", pattern: "private static let keycapSpacing: CGFloat = ([\\d.]+)" },
  { token: "--mx-session-surface-edge", file: "Components/Surface.swift", pattern: "static let borderWidth: CGFloat = ([\\d.]+)" },
  { token: "--mx-session-tile-reflection", file: "Switcher.swift", pattern: "static let reflectionOpacity = ([\\d.]+)" },
  { token: "--mx-session-tile-reflection-gap", file: "Switcher.swift", pattern: "static let reflectionGap: CGFloat = ([\\d.]+)" },
  { token: "--mx-session-failure", file: "Side/SideView.swift", pattern: "static let failure = Color\\(light: 0x([0-9A-Fa-f]+)" },
  { token: "--mx-session-failure", file: "Side/SideView.swift", pattern: "static let failure = Color\\(light: 0x[0-9A-Fa-f]+, dark: 0x([0-9A-Fa-f]+)", nth: 1 },
  { token: "--mx-session-failure", file: "Side/SideView.swift", pattern: "static let failure = Color\\(light: 0x[0-9A-Fa-f]+, dark: 0x([0-9A-Fa-f]+)", nth: 2 },
  // Settings, the first run and the scan.
  { token: "--spacing-settings-sidebar", file: "Settings/SettingsView.swift", pattern: "static let sidebarWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-sidebar", file: "Settings/SettingsView.swift", pattern: "static let sidebarInset: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-settings-sidebar-pad", file: "Settings/SettingsView.swift", pattern: "static let sidebarPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-row", file: "Settings/SettingsView.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-row-icon", file: "Settings/SettingsView.swift", pattern: "static let rowIconWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-row-icon-gap", file: "Settings/SettingsView.swift", pattern: "static let rowIconSpacing: CGFloat = ([\\d.]+)" },
  { token: "--radius-settings-row", file: "Settings/SettingsView.swift", pattern: "static let rowRadius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-header-gap", file: "Settings/SettingsView.swift", pattern: "static let headerSpacingToTitle: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-header-leading", file: "Settings/SettingsView.swift", pattern: "static let headerLeading: CGFloat = ([\\d.]+)" },
  { token: "--container-settings-page", file: "Components/SettingsKit.swift", pattern: "static let pageWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-page-pad", file: "Components/SettingsKit.swift", pattern: "static let pagePadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-row-text", file: "Components/SettingsKit.swift", pattern: "static let tileSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-row-text", file: "Components/SettingsKit.swift", pattern: "static let rowSpacing: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-settings-keycap", file: "DesignSystem.swift", pattern: "static let minimumWidth: CGFloat = ([\\d.]+)\\n\\s*private static let height: CGFloat = 18" },
  { token: "--spacing-settings-capsule", file: "Components/Controls.swift", pattern: "static let width: CGFloat = ([\\d.]+)\\n\\s*static let height: CGFloat = 32" },
  { token: "--shadow-settings-capsule", file: "Components/Controls.swift", pattern: "static let shadowDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-settings-capsule", file: "Components/Controls.swift", pattern: "static let shadowRadius: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--shadow-settings-capsule", file: "Components/Controls.swift", pattern: "static let shadow = ([\\d.]+)", part: 6 },
  { token: "--tracking-settings-code", file: "Settings/AccountPage.swift", pattern: "static let codeTracking: CGFloat = ([\\d.]+)" },
  { token: "--text-settings-fingerprint", file: "Settings/SyncPage.swift", pattern: "static let digitSize: CGFloat = ([\\d.]+)" },
  { token: "--tracking-settings-fingerprint", file: "Settings/SyncPage.swift", pattern: "static let digitTracking: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-look-width", file: "Settings/AppearancePage.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-look-height", file: "Settings/AppearancePage.swift", pattern: "static let height: CGFloat = ([\\d.]+)" },
  { token: "--shadow-settings-look-picked", file: "Settings/AppearancePage.swift", pattern: "static let ring: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--spacing-settings-live-dot", file: "Home/HomeBlocks.swift", pattern: "static let dot: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-tool-dot", file: "Tools/ToolsPage.swift", pattern: "private let toolRowDotSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-agent-label", file: "Setup.swift", pattern: "static let labelWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-menu-divider", file: "MenuBar.swift", pattern: "static let rowInset: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-menu-divider", file: "MenuBar.swift", pattern: "static let iconColumnWidth: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--spacing-settings-menu-divider", file: "MenuBar.swift", pattern: "static let iconSpacing: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--spacing-settings-step-line", file: "Setup.swift", pattern: "static let lineSpacing: CGFloat = ([\\d.]+)\\n\\s*/// Lines the mark up" },
  { token: "--spacing-settings-guide-width", file: "PermissionGuide.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-height", file: "PermissionGuide.swift", pattern: "static let headerHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-height", file: "PermissionGuide.swift", pattern: "static let rows = ([\\d.]+)", part: 1 },
  { token: "--spacing-settings-guide-height", file: "PermissionGuide.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--radius-settings-guide", file: "PermissionGuide.swift", pattern: "static let radius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-header", file: "PermissionGuide.swift", pattern: "static let headerHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-row", file: "PermissionGuide.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-tile", file: "PermissionGuide.swift", pattern: "static let tileSide: CGFloat = ([\\d.]+)" },
  { token: "--radius-settings-guide-tile", file: "PermissionGuide.swift", pattern: "static let tileRadius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-switch-width", file: "PermissionGuide.swift", pattern: "static let switchWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-switch-height", file: "PermissionGuide.swift", pattern: "static let switchHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-knob", file: "PermissionGuide.swift", pattern: "static let switchHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-settings-guide-knob", file: "PermissionGuide.swift", pattern: "static let knobInset: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--spacing-settings-guide-number", file: "PermissionGuide.swift", pattern: "static let numberSide: CGFloat = ([\\d.]+)" },
  { token: "--drop-shadow-settings-pointer", file: "PermissionGuide.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(0\\.9\\), radius: ([\\d.]+)\\)", part: 2 },
  { token: "--drop-shadow-settings-pointer", file: "PermissionGuide.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(([\\d.]+)\\), radius: 0\\.8\\)", part: 6 },
  { token: "--mx-settings-app-tiles", file: "Onboarding/AgentHomesStep.swift", pattern: "static let tileWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-onboard-top", file: "Onboarding/OnboardingCard.swift", pattern: "static let top: CGFloat = ([\\d.]+)" },
  { token: "--spacing-onboard-side", file: "Onboarding/OnboardingCard.swift", pattern: "static let side: CGFloat = ([\\d.]+)" },
  { token: "--spacing-onboard-scroll", file: "Onboarding/OnboardingCard.swift", pattern: "static let columnWidth: CGFloat = ([\\d.]+)" },
  { token: "--text-onboard-title", file: "Onboarding/OnboardingCard.swift", pattern: "private static let titleSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let wordmarkHeight: CGFloat = ([\\d.]+)" },
  { token: "--text-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let wordmarkHeight: CGFloat = ([\\d.]+)" },
  { token: "--drop-shadow-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let sheenRadius: CGFloat = ([\\d.]+)", part: 2 },
  { token: "--drop-shadow-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let sheenOpacity = ([\\d.]+)", part: 6 },
  { token: "--drop-shadow-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let glowRadius: CGFloat = ([\\d.]+)", part: 9 },
  { token: "--drop-shadow-onboard-wordmark", file: "Onboarding/OnboardingIntro.swift", pattern: "static let glowOpacity = ([\\d.]+)", part: 13 },
  { token: "--mx-onboard-veil", file: "Onboarding/OnboardingIntro.swift", pattern: "static let veilInk = ([\\d.]+)", part: 3 },
  { token: "--mx-onboard-fade", file: "Onboarding/OnboardingCard.swift", pattern: "static var fade: CGFloat \\{ ([\\d.]+) \\}", part: 1 },
  { token: "--shadow-onboard-more", file: "Onboarding/OnboardingCard.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(0\\.25\\), radius: 10, y: ([\\d.]+)\\)", part: 1 },
  { token: "--shadow-onboard-more", file: "Onboarding/OnboardingCard.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(0\\.25\\), radius: ([\\d.]+), y: 4\\)", part: 2 },
  { token: "--shadow-onboard-more", file: "Onboarding/OnboardingCard.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(([\\d.]+)\\), radius: 10, y: 4\\)", part: 6 },
  { token: "--radius-onboard-lid", file: "Onboarding/OnboardingArt.swift", pattern: "static let lidRadius: CGFloat = ([\\d.]+)" },
  { token: "--radius-onboard-screen", file: "Onboarding/OnboardingArt.swift", pattern: "static let screenRadius: CGFloat = ([\\d.]+)" },
  { token: "--radius-onboard-screen", file: "Onboarding/OnboardingArt.swift", pattern: "static let screen = CGSize\\(width: ([\\d.]+), height: 620\\)", part: 1 },
  { token: "--radius-onboard-screen", file: "Onboarding/OnboardingArt.swift", pattern: "static let screen = CGSize\\(width: 800, height: ([\\d.]+)\\)", part: 4 },
  { token: "--color-onboard-bezel", file: "Onboarding/OnboardingArt.swift", pattern: "static let bezel = Color\\(hex: 0x([0-9A-Fa-f]+)\\)" },
  { token: "--shadow-onboard-lid", file: "Onboarding/OnboardingArt.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(0\\.35\\), radius: 24, y: ([\\d.]+)\\)", part: 1 },
  { token: "--shadow-onboard-lid", file: "Onboarding/OnboardingArt.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(0\\.35\\), radius: ([\\d.]+), y: 14\\)", part: 2 },
  { token: "--shadow-onboard-lid", file: "Onboarding/OnboardingArt.swift", pattern: "\\.shadow\\(color: \\.black\\.opacity\\(([\\d.]+)\\), radius: 24, y: 14\\)", part: 6 },
  { token: "--spacing-scan-pulse", file: "ScanOverlay.swift", pattern: "private static let size: CGFloat = ([\\d.]+)" },
  { token: "--spacing-scan-badge-dot", file: "ScanOverlay.swift", pattern: "static let dot: CGFloat = ([\\d.]+)\\n\\s*static let badgeTextOpacity" },
  { token: "--text-scan-count", file: "ScanOverlay.swift", pattern: "static let countSize: CGFloat = ([\\d.]+)" },
  { token: "--text-scan-count-label", file: "ScanOverlay.swift", pattern: "static let countLabelSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-scan-card", file: "ScanOverlay.swift", pattern: "static let width: CGFloat = ([\\d.]+)\\n\\s*static let shadowOpacity = 0\\.5" },
  { token: "--spacing-scan-status-x", file: "ScanOverlay.swift", pattern: "static let statusPaddingX: CGFloat = ([\\d.]+)" },
  { token: "--spacing-scan-status-y", file: "ScanOverlay.swift", pattern: "static let statusPaddingY: CGFloat = ([\\d.]+)" },
  { token: "--shadow-scan-card", file: "ScanOverlay.swift", pattern: "static let shadowDrop: CGFloat = ([\\d.]+)\\n\\s*///[^\\n]*\\n\\s*static let hiddenScale: CGFloat = 0\\.2", part: 1 },
  { token: "--shadow-scan-card", file: "ScanOverlay.swift", pattern: "static let shadowRadius: CGFloat = ([\\d.]+)\\n\\s*static let shadowDrop: CGFloat = 10\\n\\s*///[^\\n]*\\n\\s*static let hiddenScale", part: 3 },
  { token: "--shadow-scan-card", file: "ScanOverlay.swift", pattern: "static let shadowOpacity = ([\\d.]+)\\n\\s*static let shadowRadius: CGFloat = 20", part: 7 },
  { token: "--shadow-scan-card", file: "Components/Surface.swift", pattern: "static let borderWidth: CGFloat = ([\\d.]+)", part: 11 },
  { token: "--shadow-scan-card", file: "Components/Surface.swift", pattern: "private static let borderInk = ([\\d.]+)", part: 15 },
  { token: "--spacing-scan-summary-gap", file: "ScanOverlay.swift", pattern: "static let spacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-scan-summary-pad", file: "ScanOverlay.swift", pattern: "static let paddingX: CGFloat = ([\\d.]+)" },
  { token: "--spacing-scan-divider", file: "ScanOverlay.swift", pattern: "static let dividerHeight: CGFloat = ([\\d.]+)" },
  { token: "--shadow-scan-summary", file: "ScanOverlay.swift", pattern: "static let shadowRadius: CGFloat = ([\\d.]+)\\n\\s*static let shadowDrop: CGFloat = 10\\n\\s*///[^\\n]*\\n\\s*static let hiddenDrop", part: 3 },
  { token: "--shadow-scan-summary", file: "ScanOverlay.swift", pattern: "static let shadowOpacity = ([\\d.]+)\\n\\s*static let shadowRadius: CGFloat = 24", part: 7 },
  { token: "--shadow-scan-summary", file: "ScanOverlay.swift", pattern: "static let borderOpacity = ([\\d.]+)", part: 15 },
  { token: "--mx-scan-grid-size", file: "ScanOverlay.swift", pattern: "private static let gap: CGFloat = ([\\d.]+)" },
  { token: "--mx-scan-grid", file: "DesignSystem.swift", pattern: "static let fill = ([\\d.]+)", part: 3 },
  // The island's cards, the floating cards, the tray and the orb.
  { token: "--spacing-card-call-leading", file: "Island/IslandCalls.swift", pattern: "static let textLeading: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-call-trailing", file: "Island/IslandCalls.swift", pattern: "static let textTrailing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-empty-leading", file: "Island/IslandSessionDetail.swift", pattern: "static let textLeading: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-rule-places", file: "Island/IslandRule.swift", pattern: "static let placesHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-place-y", file: "Island/IslandRule.swift", pattern: "static let vertical: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-place-icon", file: "Island/IslandRule.swift", pattern: "static let iconWidth: CGFloat = ([\\d.]+)" },
  { token: "--mx-card-rule-columns", file: "Island/IslandRule.swift", pattern: "static let labelWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-pill-y", file: "Island/IslandStyle.swift", pattern: "static let verticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-mail-row", file: "Island/IslandDraft.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-caret", file: "Island/IslandDraft.swift", pattern: "static let caretWidth: CGFloat = ([\\d.]+)" },
  { token: "--color-card-mail-red", file: "Island/IslandDraft.swift", pattern: "mailRed = Color\\(hex: 0x([0-9A-Fa-f]{6})\\)" },
  { token: "--color-card-mail-send", file: "Island/IslandDraft.swift", pattern: "sendBlue = Color\\(hex: 0x([0-9A-Fa-f]{6})\\)" },
  { token: "--spacing-card-bullet", file: "MarkdownText.swift", pattern: "static let bulletGap: CGFloat = ([\\d.]+)" },
  { token: "--text-card-code", file: "MarkdownText.swift", pattern: "static let codeTextSize: CGFloat = ([\\d.]+)" },
  { token: "--text-card-code", file: "Cards/FileList.swift", pattern: "private let codeTextSize: CGFloat = ([\\d.]+)" },
  { token: "--text-card-paragraph", file: "MarkdownText.swift", pattern: "static let paragraphTextSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-bubble", file: "Island/IslandConversation.swift", pattern: "static let maxHeight: CGFloat = ([\\d.]+)" },
  { token: "--radius-card-bubble", file: "Island/IslandConversation.swift", pattern: "static let radius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-phone-pill-y", file: "Island/IslandView.swift", pattern: "static let verticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-sign-in-y", file: "Island/IslandWork.swift", pattern: "static let horizontalPadding: CGFloat = 10\\n\\s*static let verticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-sign-in-hit", file: "Island/IslandWork.swift", pattern: "static let hitSide: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-again-badge", file: "Island/IslandWork.swift", pattern: "static let againBadge: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-work-row", file: "Island/IslandWorkCard.swift", pattern: "static let rowHeight: CGFloat = ([\\d.]+)" },
  { token: "--mx-card-work-fields", file: "Island/IslandWorkCard.swift", pattern: "static let fieldNameWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-editor-least", file: "Island/IslandWorkCard.swift", pattern: "static let editorMinHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-editor-most", file: "Island/IslandWorkCard.swift", pattern: "static let editorMaxHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-face", file: "Cards/CardPanel.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { token: "--radius-card-face", file: "Cards/CardView.swift", pattern: "static let radius: CGFloat = ([\\d.]+)" },
  { token: "--shadow-card-face", file: "Cards/CardView.swift", pattern: "static let shadowDrop: CGFloat = ([\\d.]+)", part: 1 },
  { token: "--shadow-card-face", file: "Cards/CardView.swift", pattern: "static let shadowOpacity = ([\\d.]+)", part: 6 },
  { token: "--text-card-title", file: "Cards/CardHeader.swift", pattern: "static let titleSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-close", file: "Cards/CardControls.swift", pattern: "static let target: CGFloat = ([\\d.]+)" },
  { token: "--radius-card-code", file: "Cards/FileList.swift", pattern: "static let cornerRadius: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-code-head", file: "Cards/FileList.swift", pattern: "static let headerHeight: CGFloat = ([\\d.]+)" },
  { token: "--radius-card-badge", file: "Cards/FileList.swift", pattern: "static let badgeCornerRadius: CGFloat = ([\\d.]+)" },
  { token: "--text-card-badge", file: "Cards/FileList.swift", pattern: "static let badgeTextSize: CGFloat = ([\\d.]+)" },
  { token: "--shadow-card-diff-added", file: "Cards/FileList.swift", pattern: "static let ruleWidth: CGFloat = ([\\d.]+)" },
  { token: "--shadow-card-diff-added", file: "Cards/FileList.swift", pattern: "static let ruleTint = ([\\d.]+)", part: 6 },
  { token: "--shadow-card-diff-removed", file: "Cards/FileList.swift", pattern: "static let ruleWidth: CGFloat = ([\\d.]+)" },
  { token: "--shadow-card-diff-removed", file: "Cards/FileList.swift", pattern: "static let ruleTint = ([\\d.]+)", part: 6 },
  { token: "--shadow-card-diff-same", file: "Cards/FileList.swift", pattern: "static let ruleWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-walk-page", file: "Cards/WalkView.swift", pattern: "static let pageHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-dot", file: "Cards/WalkView.swift", pattern: "static let spacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-trace-name", file: "Cards/TraceView.swift", pattern: "static let nameWidth: CGFloat = ([\\d.]+)" },
  { token: "--spacing-card-trace-duration", file: "Cards/TraceView.swift", pattern: "static let durationWidth: CGFloat = ([\\d.]+)" },
  { token: "--radius-tray-panel", file: "MenuBar.swift", pattern: "static let cornerRadius: CGFloat = ([\\d.]+)" },
  { token: "--shadow-tray-panel", file: "Components/Surface.swift", pattern: "static let borderWidth: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--radius-tray-card", file: "MenuBar.swift", pattern: "static let cardRadius: CGFloat = ([\\d.]+)" },
  { token: "--shadow-tray-rim", file: "Components/Surface.swift", pattern: "static let borderWidth: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--spacing-tray-icon-gap", file: "MenuBar.swift", pattern: "static let iconSpacing: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tray-icon-column", file: "MenuBar.swift", pattern: "static let iconColumnWidth: CGFloat = ([\\d.]+)" },
  { token: "--radius-tray-row", file: "MenuBar.swift", pattern: "static let rowCornerRadius: CGFloat = ([\\d.]+)" },
  { token: "--text-tray-title", file: "MenuBar.swift", pattern: "static let titleSize: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tray-badge-x", file: "MenuBar.swift", pattern: "static let badgeHorizontalPadding: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tray-badge-y", file: "MenuBar.swift", pattern: "static let badgeVerticalPadding: CGFloat = ([\\d.]+)" },
  { token: "--tracking-tray-heading", file: "MenuBar.swift", pattern: "static let tracking: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tray-strip", file: "MenuBar.swift", pattern: "static let stripHeight: CGFloat = ([\\d.]+)" },
  { token: "--spacing-tray-chip", file: "MenuBar.swift", pattern: "static let chipWidth: CGFloat = ([\\d.]+)" },
  { token: "--shadow-tray-dot", file: "MenuBar.swift", pattern: "static let dotRingWidth: CGFloat = ([\\d.]+)", part: 3 },
  { token: "--shadow-tray-dot", file: "MenuBar.swift", pattern: "static let dotRingInk = ([\\d.]+)", part: 7 },
  { token: "--spacing-tray-keycap", file: "DesignSystem.swift", pattern: "private static let height: CGFloat = ([\\d.]+)" },
];

/** The items of a CSS value in order, each number and each hex colour, with what `var(...)` names set aside. */
function cssItems(value: string): string[] {
  return [...value.replace(/var\([^)]*\)/g, '').matchAll(/#[0-9a-fA-F]{3,8}|-?\d*\.?\d+/g)].map(([item]) => item);
}

/** The value of a token's declaration anywhere in styles.css, the first unless `nth` asks for a later one. */
function declared(token: string, nth = 0): string {
  const found = [...css.matchAll(new RegExp(`${token.replace(/[-]/g, '\\-')}:\\s*([^;]+);`, 'g'))];
  const value = found[nth]?.[1];
  if (value === undefined) throw new Error(`styles.css has no ${token}`);
  return value.trim();
}

/** The one value `pattern` captures in a Swift source, failing where it matches none or more than one. */
function swiftValue(file: string, pattern: string): string {
  const found = [...swiftFile(file).matchAll(new RegExp(pattern, 'g'))];
  if (found.length !== 1) throw new Error(`${file}: ${pattern} matches ${found.length} times`);
  return found[0]?.[1] ?? '';
}

/** Whether a CSS item equals a Swift capture: a hex colour by its digits, a number by its value. */
function same(item: string, swiftCapture: string, scale: number): boolean {
  if (item.startsWith('#')) return item.slice(1).toLowerCase() === swiftCapture.replace(/^0x/i, '').toLowerCase();
  return Math.abs(Number(item) - Number(swiftCapture) * scale) < 1e-9;
}

/**
 * A layout constant code computes with, held to its Swift twin, as a breakpoint or a card's least width. The modules
 * are plain TypeScript so this reads them without a window.
 */
interface MacConstant {
  readonly module: string;
  readonly name: string;
  readonly key?: string;
  readonly file: string;
  readonly pattern: string;
}

const MODULES: Record<string, Record<string, unknown>> = {
  'src/core/domain/menu-panel.ts': menuPanel,
  'src/ui/app/page-metrics.ts': pageMetrics,
  'src/ui/scan/scan-layout.ts': scanLayout,
  'src/ui/sessions/session-metrics.ts': sessionMetrics,
};

const MAC_CONSTANTS: readonly MacConstant[] = [
  // The Memnox window's pages, for the widths they hand to a style.
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "projectSearch", file: "App/ProjectsDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "skillVersion", file: "App/SkillSheets.swift", pattern: "static let versionWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "skillInstructions", file: "App/SkillSheets.swift", pattern: "static let instructionsHeight: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "activitySearch", file: "App/ActivityDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "activityKind", file: "App/ActivityDestination.swift", pattern: "static let kindWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "hubSearch", file: "App/McpHubDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "skillProgress", file: "App/SkillsDestination.swift", pattern: "static let progressWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "discoverSearch", file: "App/DiscoverDestination.swift", pattern: "static let searchWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "discoverAddress", file: "App/DiscoverDestination.swift", pattern: "static let addressWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/app/page-metrics.ts", name: "PAGE_METRICS", key: "homeTrack", file: "App/HomeStart.swift", pattern: "static let trackMinimum: CGFloat = ([\\d.]+)" },
  // The session windows, the island's session screens and the side panel.
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_SHAPE", key: "flare", file: "Island/IslandLayout.swift", pattern: "static let flare: CGFloat = ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_SHAPE", key: "radius", file: "Side/SideView.swift", pattern: "static let cornerRadius: CGFloat = ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_SHAPE", key: "padding", file: "Side/SideView.swift", pattern: "static let flare = Island.flare\\n\\s+static let padding: CGFloat = ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_TAB", key: "resting.width", file: "Side/SidePanel.swift", pattern: "restingTab = CGSize\\(width: ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_TAB", key: "resting.height", file: "Side/SidePanel.swift", pattern: "restingTab = CGSize\\(width: [\\d.]+, height: ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_TAB", key: "hovering.width", file: "Side/SidePanel.swift", pattern: "hoveringTab = CGSize\\(width: ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_TAB", key: "hovering.height", file: "Side/SidePanel.swift", pattern: "hoveringTab = CGSize\\(width: [\\d.]+, height: ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "SIDE_TAB", key: "slop", file: "Side/SidePanel.swift", pattern: "static let tabSlop: CGFloat = ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "WALL", key: "cardWidth", file: "Cards/CardPanel.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { module: "src/ui/sessions/session-metrics.ts", name: "WALL", key: "gap", file: "Cards/CardWall.swift", pattern: "private static let gap: CGFloat = ([\\d.]+)" },
  // Settings, the first run and the scan.
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "centreDrop", file: "ScanOverlay.swift", pattern: "static let centreDrop: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "headingTop", file: "ScanOverlay.swift", pattern: "static let headingTop: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "summaryBottom", file: "ScanOverlay.swift", pattern: "static let summaryFromBottom: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "rayOpacity", file: "ScanOverlay.swift", pattern: "static let lineOpacity = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "rayWidth", file: "ScanOverlay.swift", pattern: "static let lineWidth: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "lightGlow", file: "ScanOverlay.swift", pattern: "static let lightGlow: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "ringScanning", file: "ScanOverlay.swift", pattern: "static let scanningOpacity = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "ringFound", file: "ScanOverlay.swift", pattern: "static let restingOpacity = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "leavingScale", file: "ScanOverlay.swift", pattern: "static let leavingScale: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "leavingBlur", file: "ScanOverlay.swift", pattern: "static let leavingBlur: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "summaryDrop", file: "ScanOverlay.swift", pattern: "static let hiddenDrop: CGFloat = ([\\d.]+)" },
  { module: "src/ui/scan/scan-layout.ts", name: "SCAN_LAYOUT", key: "logo", file: "ScanOverlay.swift", pattern: "static let logo: CGFloat = ([\\d.]+)" },
  // The island's cards, the floating cards, the tray and the orb.
  { module: "src/core/domain/menu-panel.ts", name: "MENU_PANEL", key: "width", file: "MenuBar.swift", pattern: "static let width: CGFloat = ([\\d.]+)" },
  { module: "src/core/domain/menu-panel.ts", name: "MENU_PANEL", key: "gap", file: "MenuBar.swift", pattern: "static let gap: CGFloat = ([\\d.]+)" },
  { module: "src/core/domain/menu-panel.ts", name: "MENU_PANEL", key: "inset", file: "MenuBar.swift", pattern: "static let screenMargin: CGFloat = ([\\d.]+)" },
];

function constantOf(row: MacConstant): unknown {
  const root = MODULES[row.module]?.[row.name];
  return (row.key ?? '').split('.').filter((step) => step !== '').reduce<unknown>((at, step) => (at as Record<string, unknown> | undefined)?.[step], root);
}

describe('the page tokens', () => {
  it('hold every page measure and colour to the Mac view that draws it', () => {
    const drifted: string[] = [];
    for (const row of MAC_METRICS) {
      const item = cssItems(declared(row.token, row.nth))[row.part ?? 0];
      const swiftCapture = swiftValue(row.file, row.pattern);
      if (item === undefined || !same(item, swiftCapture, row.scale ?? 1)) drifted.push(`${row.token}[${row.part ?? 0}] is ${item}, the Mac's ${row.file} says ${swiftCapture}`);
    }
    expect(drifted).toEqual([]);
    expect(MAC_METRICS.length).toBeGreaterThan(LEAST_COMPARED);
  });

  it('hold the layout constants code computes with to the Mac', () => {
    const drifted: string[] = [];
    for (const row of MAC_CONSTANTS) {
      const value = constantOf(row);
      const swiftCapture = swiftValue(row.file, row.pattern);
      if (typeof value !== 'number' || !same(String(value), swiftCapture, 1)) drifted.push(`${row.name}.${row.key ?? ''} is ${String(value)}, the Mac's ${row.file} says ${swiftCapture}`);
    }
    expect(drifted).toEqual([]);
  });

  it('give layout code the Mac spacing as numbers, the same steps as the CSS', () => {
    const spacing = swiftEnum('Spacing');
    const root = cssBlock(':root');
    const short: Record<keyof typeof SPACING, string> = { xxSmall: 'xxs', xSmall: 'xs', small: 'sm', medium: 'md', regular: 'rg', large: 'lg', xLarge: 'xl', xxLarge: 'xxl' };
    for (const [name, value] of Object.entries(SPACING) as [keyof typeof SPACING, number][]) {
      expect([name, value]).toEqual([name, swiftNumber(spacing, name)]);
      expect([name, cssPixels(root, `--mx-space-${short[name]}`)]).toEqual([name, value]);
    }
  });

  it('fade the top bar presses as far as the Mac does', () => {
    const fade = /opacity-(\d+)/.exec(ICON_BUTTON_FADE.bar)?.[1];
    expect(Number(fade) / 100).toBe(Number(swiftValue('App/AppShellView.swift', 'static let disabledOpacity = ([\\d.]+)')));
  });
});
