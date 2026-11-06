import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

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
