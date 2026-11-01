/**
 * What the cloud's brain map borrowed from the rest of the console, made here for the desktop: the colour probe the
 * canvas resolves its ink through, the pixel ratio it stops at, and the bundled marks the core names by key, the Mac's
 * own logo files, so the brain wears the same marks as every other window.
 */

/** The device pixel ratio is read up to this, since a sharper glow is not worth four times the fill. */
export const MOST_PIXEL_RATIO = 2;

/** Each mark the core names, `agent:` or `tool:` and the file, as Vite serves it. */
const MARKS: Readonly<Record<string, string>> = {
  'agent:claude': new URL('../../../assets/agents/claude.svg', import.meta.url).href,
  'agent:cursor': new URL('../../../assets/agents/cursor.svg', import.meta.url).href,
  'agent:openai': new URL('../../../assets/agents/openai.svg', import.meta.url).href,
  'agent:copilot': new URL('../../../assets/agents/copilot.svg', import.meta.url).href,
  'agent:opencode': new URL('../../../assets/agents/opencode.svg', import.meta.url).href,
  'agent:cline': new URL('../../../assets/agents/cline.webp', import.meta.url).href,
  'agent:hermes': new URL('../../../assets/agents/hermes.webp', import.meta.url).href,
  'agent:openclaw': new URL('../../../assets/agents/openclaw.webp', import.meta.url).href,
  'agent:antigravity': new URL('../../../assets/agents/antigravity.svg', import.meta.url).href,
  'tool:slack': new URL('../../../assets/tools/slack.svg', import.meta.url).href,
  'tool:github': new URL('../../../assets/tools/github.svg', import.meta.url).href,
  'tool:linear': new URL('../../../assets/tools/linear.svg', import.meta.url).href,
  'tool:gmail': new URL('../../../assets/tools/gmail.svg', import.meta.url).href,
  'tool:googledocs': new URL('../../../assets/tools/googledocs.svg', import.meta.url).href,
  'tool:notion': new URL('../../../assets/tools/notion.svg', import.meta.url).href,
};

/** The file a mark key names, or the key itself where it is already an address. */
export function markUrl(key: string): string {
  return MARKS[key] ?? key;
}

/** Grey, where a colour cannot be resolved. */
const FALLBACK_CHANNEL = 128;
const FALLBACK_RGB = `${FALLBACK_CHANNEL},${FALLBACK_CHANNEL},${FALLBACK_CHANNEL}`;
/** Alpha to three decimals, which is finer than any screen shows. */
const ALPHA_PRECISION = 1000;

/**
 * Turns a colour as the stylesheet writes it into one the canvas can mix an alpha into. A probe resolves a variable
 * and a one pixel canvas the colour space, made fresh per paint so a theme switched since is read again.
 */
export function paintFor(probe: HTMLElement | null): (css: string, alpha: number) => string {
  const known = new Map<string, string>();
  const canvas = document.createElement('canvas');
  canvas.width = 1;
  canvas.height = 1;
  const pen = canvas.getContext('2d', { willReadFrequently: true });
  const rgbOf = (css: string): string => {
    const cached = known.get(css);
    if (cached !== undefined) return cached;
    const rgb = probe !== null && pen !== null ? resolved(css, probe, pen) : FALLBACK_RGB;
    known.set(css, rgb);
    return rgb;
  };
  return (css, alpha) => `rgba(${rgbOf(css)},${Math.round(alpha * ALPHA_PRECISION) / ALPHA_PRECISION})`;
}

function resolved(css: string, probe: HTMLElement, pen: CanvasRenderingContext2D): string {
  probe.style.color = css;
  pen.clearRect(0, 0, 1, 1);
  pen.fillStyle = getComputedStyle(probe).color;
  pen.fillRect(0, 0, 1, 1);
  const [red, green, blue] = pen.getImageData(0, 0, 1, 1).data;
  return `${red ?? FALLBACK_CHANNEL},${green ?? FALLBACK_CHANNEL},${blue ?? FALLBACK_CHANNEL}`;
}
