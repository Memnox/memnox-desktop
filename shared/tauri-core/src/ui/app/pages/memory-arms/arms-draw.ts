/**
 * The marks of the ARMS map, each a few canvas calls, so the loop can draw
 * thousands of them in one frame. Everything here is in CSS pixels; the
 * engine sets the device ratio once on the context.
 */

export type Pen = {
  ctx: CanvasRenderingContext2D;
  /** A theme colour resolved to rgba at an alpha the canvas can parse. */
  paint: (css: string, alpha: number) => string;
  /** The interface face as the page resolved it, since a canvas font cannot read a variable. */
  family: string;
};

/** The effect a rule names, and the colour its dot on the gold ring wears. */
export const EFFECT_INK: Record<string, string> = {
  allow: "#37CD8F",
  ask: "#F5C542",
  deny: "#E31957",
};

/** Each bucket is one fill call: dots of one colour at one alpha. */
export type DotBucket = { ink: string; alpha: number; xy: number[]; size: number[] };

export function fillDots(pen: Pen, buckets: readonly DotBucket[]): void {
  const { ctx } = pen;
  for (const bucket of buckets) {
    if (bucket.xy.length === 0 || bucket.alpha <= 0) continue;
    ctx.fillStyle = pen.paint(bucket.ink, bucket.alpha);
    ctx.beginPath();
    for (let index = 0; index < bucket.size.length; index += 1) {
      const size = bucket.size[index]!;
      ctx.rect(bucket.xy[index * 2]! - size / 2, bucket.xy[index * 2 + 1]! - size / 2, size, size);
    }
    ctx.fill();
  }
}

/** A four point star, the skills' mark, with its waist pinched to a sparkle. */
export function starPath(ctx: CanvasRenderingContext2D, x: number, y: number, r: number): void {
  const waist = r * 0.28;
  ctx.beginPath();
  ctx.moveTo(x, y - r);
  ctx.quadraticCurveTo(x + waist * 0.3, y - waist * 0.3, x + r, y);
  ctx.quadraticCurveTo(x + waist * 0.3, y + waist * 0.3, x, y + r);
  ctx.quadraticCurveTo(x - waist * 0.3, y + waist * 0.3, x - r, y);
  ctx.quadraticCurveTo(x - waist * 0.3, y - waist * 0.3, x, y - r);
  ctx.closePath();
}

/** A soft round glow, the bloom a star ignites with and the halo a hovered mark wears. */
export function glow(pen: Pen, x: number, y: number, r: number, ink: string, alpha: number): void {
  if (alpha <= 0.002 || r <= 0) return;
  const { ctx } = pen;
  const gradient = ctx.createRadialGradient(x, y, 0, x, y, r);
  gradient.addColorStop(0, pen.paint(ink, alpha));
  gradient.addColorStop(1, pen.paint(ink, 0));
  ctx.fillStyle = gradient;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

/** A line through screen points, drawn up to `share` of its length, as the rules ring draws itself. */
export function strokeShare(pen: Pen, xy: readonly number[], share: number, ink: string, alpha: number, width: number, closed: boolean): void {
  const points = xy.length / 2;
  const upTo = Math.floor(points * Math.min(1, share));
  if (upTo < 2) return;
  const { ctx } = pen;
  ctx.strokeStyle = pen.paint(ink, alpha);
  ctx.lineWidth = width;
  ctx.beginPath();
  ctx.moveTo(xy[0]!, xy[1]!);
  for (let index = 1; index < upTo; index += 1) ctx.lineTo(xy[index * 2]!, xy[index * 2 + 1]!);
  if (closed && share >= 1) ctx.closePath();
  ctx.stroke();
}

/** The air between two spaced capitals, in pixels. */
const SPACING = 2.6;

/** A label in spaced capitals, centred on its point, the way the layer names read. */
export function spacedCaps(pen: Pen, text: string, x: number, y: number, ink: string, alpha: number): void {
  const { ctx } = pen;
  ctx.font = `600 10px ${pen.family}`;
  ctx.fillStyle = pen.paint(ink, alpha);
  ctx.textBaseline = "middle";
  const letters = [...text.toUpperCase()];
  const width = letters.reduce((sum, letter) => sum + ctx.measureText(letter).width + SPACING, -SPACING);
  let at = x - width / 2;
  for (const letter of letters) {
    ctx.fillText(letter, at, y);
    at += ctx.measureText(letter).width + SPACING;
  }
}

export function plainLabel(pen: Pen, text: string, x: number, y: number, ink: string, alpha: number, align: CanvasTextAlign = "center"): void {
  const { ctx } = pen;
  ctx.font = `500 11px ${pen.family}`;
  ctx.fillStyle = pen.paint(ink, alpha);
  ctx.textAlign = align;
  ctx.textBaseline = "top";
  ctx.fillText(text, x, y);
  ctx.textAlign = "left";
}

/** An app's tile: a circle on the ground with the console's blue glow and its logo inside. */
export function appTile(pen: Pen, x: number, y: number, r: number, logo: HTMLImageElement | undefined, initial: string, alpha: number, lit: number, ink: { ground: string; glow: string; text: string }): void {
  const { ctx } = pen;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.shadowColor = pen.paint(ink.glow, 0.4 + 0.35 * lit);
  ctx.shadowBlur = 6 + 10 * lit;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = pen.paint(ink.ground, 1);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.lineWidth = 1.4;
  ctx.strokeStyle = pen.paint(ink.glow, 0.6 + 0.4 * lit);
  ctx.stroke();
  if (logo !== undefined && logo.complete && logo.naturalWidth > 0) {
    const size = r * 1.1;
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, r * 0.82, 0, Math.PI * 2);
    ctx.clip();
    ctx.drawImage(logo, x - size / 2, y - size / 2, size, size);
    ctx.restore();
  } else {
    ctx.font = `600 ${Math.round(Math.max(9, r * 0.8))}px ${pen.family}`;
    ctx.fillStyle = pen.paint(ink.text, 0.9);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(initial, x, y);
    ctx.textAlign = "left";
  }
  ctx.restore();
}

/** An app's number round the ring, a small filled disc on its tile's shoulder. */
export function badge(pen: Pen, x: number, y: number, text: string, alpha: number, ink: { fill: string; text: string }): void {
  const { ctx } = pen;
  ctx.font = `700 9px ${pen.family}`;
  const r = Math.max(7, ctx.measureText(text).width / 2 + 4);
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = pen.paint(ink.fill, alpha);
  ctx.fill();
  ctx.fillStyle = pen.paint(ink.text, alpha);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, x, y + 0.5);
  ctx.textAlign = "left";
}

/** How long ago an app last delivered, as a capsule under its tile. */
export function chip(pen: Pen, x: number, y: number, text: string, alpha: number, ink: { ground: string; border: string; text: string }): number {
  const { ctx } = pen;
  ctx.font = `600 9px ${pen.family}`;
  const width = ctx.measureText(text).width + 10;
  const height = 13;
  const left = x - width / 2;
  ctx.beginPath();
  ctx.roundRect(left, y, width, height, height / 2);
  ctx.fillStyle = pen.paint(ink.ground, alpha);
  ctx.fill();
  ctx.lineWidth = 1;
  ctx.strokeStyle = pen.paint(ink.border, alpha);
  ctx.stroke();
  ctx.fillStyle = pen.paint(ink.text, alpha);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, x, y + height / 2 + 0.5);
  ctx.textAlign = "left";
  return height;
}

/** A spoke from one mark to another, bowed to one side so a fan of them reads as a fan. */
export function curve(ctx: CanvasRenderingContext2D, ax: number, ay: number, bx: number, by: number, bend: number): void {
  const mx = (ax + bx) / 2;
  const my = (ay + by) / 2;
  ctx.moveTo(ax, ay);
  ctx.quadraticCurveTo(mx - (by - ay) * bend, my + (bx - ax) * bend, bx, by);
}

/** A name on the map, haloed in the ground colour so it reads over the dust. */
export function haloLabel(pen: Pen, text: string, x: number, top: number, font: string, ink: string, ground: string, alpha: number): void {
  const { ctx } = pen;
  ctx.font = font;
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  ctx.lineJoin = "round";
  ctx.lineWidth = 3;
  ctx.strokeStyle = pen.paint(ground, 0.85 * alpha);
  ctx.strokeText(text, x, top);
  ctx.fillStyle = pen.paint(ink, alpha);
  ctx.fillText(text, x, top);
  ctx.textAlign = "left";
}

/** The width spaced capitals take, so a layer's caption can hold its place among the names. */
export function spacedWidth(pen: Pen, text: string): number {
  const { ctx } = pen;
  ctx.font = `600 10px ${pen.family}`;
  return [...text.toUpperCase()].reduce((sum, letter) => sum + ctx.measureText(letter).width + SPACING, -SPACING);
}

/** A rule on the gold ring: a small gold circle, its centre in the colour of its effect. */
export function ruleMark(pen: Pen, x: number, y: number, r: number, effect: string | undefined, alpha: number, ink: { gold: string; ground: string }): void {
  const { ctx } = pen;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = pen.paint(ink.ground, alpha);
  ctx.fill();
  ctx.lineWidth = 1.5;
  ctx.strokeStyle = pen.paint(ink.gold, alpha);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(x, y, r * 0.42, 0, Math.PI * 2);
  ctx.fillStyle = pen.paint(EFFECT_INK[effect ?? ""] ?? ink.gold, alpha);
  ctx.fill();
}

/** A travelling arrival: its head bright, its trail fading behind it. */
export function particle(pen: Pen, trail: readonly number[], ink: string, alpha: number): void {
  const points = trail.length / 2;
  if (points === 0) return;
  const { ctx } = pen;
  ctx.lineCap = "round";
  for (let index = 1; index < points; index += 1) {
    const share = index / points;
    ctx.strokeStyle = pen.paint(ink, alpha * share * 0.8);
    ctx.lineWidth = 0.6 + share * 2.4;
    ctx.beginPath();
    ctx.moveTo(trail[(index - 1) * 2]!, trail[(index - 1) * 2 + 1]!);
    ctx.lineTo(trail[index * 2]!, trail[index * 2 + 1]!);
    ctx.stroke();
  }
  const hx = trail[(points - 1) * 2]!;
  const hy = trail[(points - 1) * 2 + 1]!;
  glow(pen, hx, hy, 12, ink, alpha * 0.9);
  ctx.fillStyle = pen.paint("white", alpha);
  ctx.beginPath();
  ctx.arc(hx, hy, 2.2, 0, Math.PI * 2);
  ctx.fill();
}

/** Somebody as a circle: their picture clipped round, else their initials on their own colour. */
export function face(pen: Pen, x: number, y: number, r: number, picture: HTMLImageElement | undefined, initials: string, ink: string, alpha: number, ground: string): void {
  const { ctx } = pen;
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = pen.paint(ink, alpha);
  ctx.fill();
  if (picture !== undefined) {
    ctx.globalAlpha *= alpha;
    ctx.clip();
    ctx.drawImage(picture, x - r, y - r, r * 2, r * 2);
  } else if (r >= 6) {
    ctx.font = `600 ${Math.round(r * 0.8)}px ${pen.family}`;
    ctx.fillStyle = pen.paint("white", alpha);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(initials, x, y + 0.5);
    ctx.textAlign = "left";
  }
  ctx.restore();
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.lineWidth = 1.2;
  ctx.strokeStyle = pen.paint(ground, 0.9 * alpha);
  ctx.stroke();
}

/** A brand mark inside a disc, clipped round so a square logo sits in a round hub. */
export function markIn(pen: Pen, x: number, y: number, r: number, mark: HTMLImageElement, alpha: number): void {
  const { ctx } = pen;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.clip();
  const size = r * 1.3;
  ctx.drawImage(mark, x - size / 2, y - size / 2, size, size);
  ctx.restore();
}
