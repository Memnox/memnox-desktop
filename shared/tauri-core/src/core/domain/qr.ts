/**
 * A QR code encoder, so pairing a phone draws its code with no package, as the Mac draws it with
 * CoreImage. A fresh port of Nayuki's qrcodegen: byte mode only, the smallest version that fits,
 * and the mask the standard penalty rules like best.
 */

/** How much of the code can be lost and still read, from least to most. */
export type QrLevel = 'L' | 'M' | 'Q' | 'H';

/** The two format bits each level writes, from the standard. */
const FORMAT_BITS: Record<QrLevel, number> = { L: 1, M: 0, Q: 3, H: 2 };
/** Each level's row in the tables below. */
const LEVEL_ROW: Record<QrLevel, number> = { L: 0, M: 1, Q: 2, H: 3 };

const MIN_VERSION = 1;
const MAX_VERSION = 40;
/** The byte mode indicator, four bits. */
const BYTE_MODE = 0x4;
/** Pad codewords alternate between these two once the data runs out. */
const PAD_BYTES = [0xec, 0x11] as const;
/** The generator polynomial of the format and version BCH codes. */
const FORMAT_GENERATOR = 0x537;
const FORMAT_XOR = 0x5412;
const VERSION_GENERATOR = 0x1f25;
/** The Reed Solomon field's reducing polynomial, x^8 + x^4 + x^3 + x^2 + 1. */
const FIELD_POLY = 0x11d;
/** Penalty weights N1 to N4 of the mask rules. */
const PENALTY_N1 = 3;
const PENALTY_N2 = 3;
const PENALTY_N3 = 40;
const PENALTY_N4 = 10;

/** Error correction codewords per block, by level then version (index 0 unused). */
const ECC_PER_BLOCK: readonly (readonly number[])[] = [
  [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
  [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
];

/** Error correction blocks, by level then version (index 0 unused). */
const BLOCK_COUNT: readonly (readonly number[])[] = [
  [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
  [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
  [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
  [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
];

/** How many masks the standard defines. */
const MASK_COUNT = 8;

/** Whether the module at x, y flips under one of the eight masks. */
function flips(mask: number, x: number, y: number): boolean {
  switch (mask) {
    case 0:
      return (x + y) % 2 === 0;
    case 1:
      return y % 2 === 0;
    case 2:
      return x % 3 === 0;
    case 3:
      return (x + y) % 3 === 0;
    case 4:
      return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
    case 5:
      return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6:
      return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    default:
      return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
  }
}

/** One cell of a per level, per version table. */
function tableEntry(table: readonly (readonly number[])[], level: QrLevel, version: number): number {
  return table[LEVEL_ROW[level]]?.[version] ?? 0;
}

/** The text as UTF-8 bytes, written out here since the core has no TextEncoder. */
function utf8(text: string): number[] {
  const bytes: number[] = [];
  for (const letter of text) {
    const point = letter.codePointAt(0) ?? 0;
    if (point < 0x80) bytes.push(point);
    else if (point < 0x800) bytes.push(0xc0 | (point >> 6), 0x80 | (point & 0x3f));
    else if (point < 0x10000) bytes.push(0xe0 | (point >> 12), 0x80 | ((point >> 6) & 0x3f), 0x80 | (point & 0x3f));
    else bytes.push(0xf0 | (point >> 18), 0x80 | ((point >> 12) & 0x3f), 0x80 | ((point >> 6) & 0x3f), 0x80 | (point & 0x3f));
  }
  return bytes;
}

/** The square of modules for `text` (true is dark), with no quiet zone; throws when it is too long for version 40. */
export function qrModules(text: string, level: QrLevel = 'M'): boolean[][] {
  const data = utf8(text);
  let version = MIN_VERSION;
  for (; ; version += 1) {
    if (version > MAX_VERSION) throw new RangeError('too long for a QR code');
    if (bitsNeeded(data.length, version) <= dataCodewords(version, level) * 8) break;
  }
  const codewords = withErrorCorrection(dataBits(data, version, level), version, level);
  const code = new QrDrawing(version);
  code.drawFunctionPatterns();
  code.drawCodewords(codewords);
  let best = 0;
  let lowest = Infinity;
  for (let mask = 0; mask < MASK_COUNT; mask += 1) {
    code.applyMask(mask);
    code.drawFormat(level, mask);
    const penalty = code.penalty();
    if (penalty < lowest) {
      lowest = penalty;
      best = mask;
    }
    // A mask is its own undo.
    code.applyMask(mask);
  }
  code.applyMask(best);
  code.drawFormat(level, best);
  return code.rows();
}

/** An SVG path of the dark modules, a run of them on a row as one rectangle, drawn in a viewBox the code's size. */
export function qrPath(modules: boolean[][]): string {
  const parts: string[] = [];
  modules.forEach((row, y) => {
    let x = 0;
    while (x < row.length) {
      if (!row[x]) {
        x += 1;
        continue;
      }
      let run = 1;
      while (row[x + run] === true) run += 1;
      parts.push(`M${x} ${y}h${run}v1h-${run}z`);
      x += run;
    }
  });
  return parts.join('');
}

/** The side of a version's square, 21 for version 1 and four more each version. */
export function qrSize(version: number): number {
  return version * 4 + 17;
}

/** Bits the mode, the count and the bytes take in a version. */
function bitsNeeded(bytes: number, version: number): number {
  return 4 + countBits(version) + bytes * 8;
}

/** The byte count field is 8 bits up to version 9 and 16 after. */
function countBits(version: number): number {
  return version < 10 ? 8 : 16;
}

/** Every module that carries data or its correction, which is everything but the function patterns. */
function rawDataModules(version: number): number {
  let result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    const aligns = Math.floor(version / 7) + 2;
    result -= (25 * aligns - 10) * aligns - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

function dataCodewords(version: number, level: QrLevel): number {
  return Math.floor(rawDataModules(version) / 8) - tableEntry(ECC_PER_BLOCK, level, version) * tableEntry(BLOCK_COUNT, level, version);
}

/** The data codewords: mode, count, bytes, terminator and padding. */
function dataBits(data: number[], version: number, level: QrLevel): number[] {
  const bits: number[] = [];
  const put = (value: number, length: number) => {
    for (let at = length - 1; at >= 0; at -= 1) bits.push((value >>> at) & 1);
  };
  put(BYTE_MODE, 4);
  put(data.length, countBits(version));
  for (const byte of data) put(byte, 8);
  const capacity = dataCodewords(version, level) * 8;
  put(0, Math.min(4, capacity - bits.length));
  put(0, (8 - (bits.length % 8)) % 8);
  for (let pad = 0; bits.length < capacity; pad += 1) put(pad % 2 === 0 ? PAD_BYTES[0] : PAD_BYTES[1], 8);
  const bytes: number[] = [];
  for (let at = 0; at < bits.length; at += 8) {
    let byte = 0;
    for (let bit = 0; bit < 8; bit += 1) byte = (byte << 1) | (bits[at + bit] ?? 0);
    bytes.push(byte);
  }
  return bytes;
}

/** Splits the data into blocks, adds each block's correction, and interleaves them as the standard reads them. */
export function withErrorCorrection(data: number[], version: number, level: QrLevel): number[] {
  const blocks = tableEntry(BLOCK_COUNT, level, version);
  const eccLength = tableEntry(ECC_PER_BLOCK, level, version);
  const raw = Math.floor(rawDataModules(version) / 8);
  const shortBlocks = blocks - (raw % blocks);
  const shortLength = Math.floor(raw / blocks);
  const divisor = reedSolomonDivisor(eccLength);
  const all: number[][] = [];
  for (let block = 0, at = 0; block < blocks; block += 1) {
    const length = shortLength - eccLength + (block < shortBlocks ? 0 : 1);
    const chunk = data.slice(at, at + length);
    at += length;
    const ecc = reedSolomonRemainder(chunk, divisor);
    // A short block keeps a gap so every block lines up when interleaved.
    if (block < shortBlocks) chunk.push(-1);
    all.push([...chunk, ...ecc]);
  }
  const result: number[] = [];
  // Every block is one longer than a short block's real length, since the short ones carry the gap.
  for (let at = 0; at <= shortLength; at += 1) {
    all.forEach((block, index) => {
      if (at !== shortLength - eccLength || index >= shortBlocks) result.push(block[at] ?? 0);
    });
  }
  return result;
}

/** The generator polynomial of a Reed Solomon code with this many correction codewords. */
function reedSolomonDivisor(degree: number): number[] {
  const result = new Array<number>(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let step = 0; step < degree; step += 1) {
    for (let at = 0; at < degree; at += 1) {
      result[at] = multiply(result[at] ?? 0, root) ^ (at + 1 < degree ? (result[at + 1] ?? 0) : 0);
    }
    root = multiply(root, 0x02);
  }
  return result;
}

/** The correction codewords of a block, the remainder of dividing it by the generator. */
export function reedSolomonRemainder(data: number[], divisor: number[]): number[] {
  const result = new Array<number>(divisor.length).fill(0);
  for (const byte of data) {
    const factor = byte ^ (result.shift() ?? 0);
    result.push(0);
    divisor.forEach((coefficient, at) => {
      result[at] = (result[at] ?? 0) ^ multiply(coefficient, factor);
    });
  }
  return result;
}

/** Multiplication in GF(2^8) over the QR field polynomial. */
function multiply(x: number, y: number): number {
  let z = 0;
  for (let bit = 7; bit >= 0; bit -= 1) {
    z = (z << 1) ^ ((z >>> 7) * FIELD_POLY);
    z ^= ((y >>> bit) & 1) * x;
  }
  return z;
}

/** Where the alignment patterns sit on each axis of a version. */
function alignmentPositions(version: number): number[] {
  if (version === 1) return [];
  const count = Math.floor(version / 7) + 2;
  const step = version === 32 ? 26 : Math.ceil((version * 4 + 4) / (count * 2 - 2)) * 2;
  const result = [6];
  for (let position = qrSize(version) - 7; result.length < count; position -= step) result.splice(1, 0, position);
  return result;
}

/** The 15 format bits for a level and a mask, BCH coded and masked. */
export function formatBits(level: QrLevel, mask: number): number {
  const data = (FORMAT_BITS[level] << 3) | mask;
  let remainder = data;
  for (let step = 0; step < 10; step += 1) remainder = (remainder << 1) ^ ((remainder >>> 9) * FORMAT_GENERATOR);
  return ((data << 10) | remainder) ^ FORMAT_XOR;
}

/** The grid as it is drawn, with which modules belong to the function patterns and so are never masked. */
class QrDrawing {
  readonly size: number;
  /** Dark or light, row after row. */
  private readonly dark: boolean[];
  /** Whether a module belongs to a function pattern, which no data and no mask touches. */
  private readonly fixed: boolean[];

  constructor(private readonly version: number) {
    this.size = qrSize(version);
    this.dark = new Array<boolean>(this.size * this.size).fill(false);
    this.fixed = new Array<boolean>(this.size * this.size).fill(false);
  }

  isDark(x: number, y: number): boolean {
    return this.dark[y * this.size + x] === true;
  }

  private isFixed(x: number, y: number): boolean {
    return this.fixed[y * this.size + x] === true;
  }

  private paint(x: number, y: number, dark: boolean): void {
    this.dark[y * this.size + x] = dark;
  }

  rows(): boolean[][] {
    return Array.from({ length: this.size }, (_, y) => Array.from({ length: this.size }, (_unused, x) => this.isDark(x, y)));
  }

  drawFunctionPatterns(): void {
    for (let at = 0; at < this.size; at += 1) {
      this.set(6, at, at % 2 === 0);
      this.set(at, 6, at % 2 === 0);
    }
    this.drawFinder(3, 3);
    this.drawFinder(this.size - 4, 3);
    this.drawFinder(3, this.size - 4);
    const aligns = alignmentPositions(this.version);
    const last = aligns.length - 1;
    aligns.forEach((x, i) =>
      aligns.forEach((y, j) => {
        // The three corners hold finders, not alignment patterns.
        if (!((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0))) this.drawAlignment(x, y);
      }),
    );
    // Reserved now, written for real once the mask is chosen.
    this.drawFormat('M', 0);
    this.drawVersion();
  }

  /** Writes the format bits around the top left finder and split between the other two. */
  drawFormat(level: QrLevel, mask: number): void {
    const bits = formatBits(level, mask);
    const bit = (at: number) => ((bits >>> at) & 1) !== 0;
    for (let at = 0; at <= 5; at += 1) this.set(8, at, bit(at));
    this.set(8, 7, bit(6));
    this.set(8, 8, bit(7));
    this.set(7, 8, bit(8));
    for (let at = 9; at < 15; at += 1) this.set(14 - at, 8, bit(at));
    for (let at = 0; at < 8; at += 1) this.set(this.size - 1 - at, 8, bit(at));
    for (let at = 8; at < 15; at += 1) this.set(8, this.size - 15 + at, bit(at));
    // The one module that is always dark.
    this.set(8, this.size - 8, true);
  }

  private drawVersion(): void {
    if (this.version < 7) return;
    let remainder = this.version;
    for (let step = 0; step < 12; step += 1) remainder = (remainder << 1) ^ ((remainder >>> 11) * VERSION_GENERATOR);
    const bits = (this.version << 12) | remainder;
    for (let at = 0; at < 18; at += 1) {
      const dark = ((bits >>> at) & 1) !== 0;
      const a = this.size - 11 + (at % 3);
      const b = Math.floor(at / 3);
      this.set(a, b, dark);
      this.set(b, a, dark);
    }
  }

  private drawFinder(x: number, y: number): void {
    for (let dy = -4; dy <= 4; dy += 1) {
      for (let dx = -4; dx <= 4; dx += 1) {
        const distance = Math.max(Math.abs(dx), Math.abs(dy));
        const xx = x + dx;
        const yy = y + dy;
        if (xx >= 0 && xx < this.size && yy >= 0 && yy < this.size) this.set(xx, yy, distance !== 2 && distance !== 4);
      }
    }
  }

  private drawAlignment(x: number, y: number): void {
    for (let dy = -2; dy <= 2; dy += 1) {
      for (let dx = -2; dx <= 2; dx += 1) this.set(x + dx, y + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
  }

  private set(x: number, y: number, dark: boolean): void {
    this.paint(x, y, dark);
    this.fixed[y * this.size + x] = true;
  }

  /** Lays the codewords in the zigzag of two column strips, right to left, skipping the timing column. */
  drawCodewords(codewords: number[]): void {
    let at = 0;
    const total = codewords.length * 8;
    for (let right = this.size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let step = 0; step < this.size; step += 1) {
        for (let column = 0; column < 2; column += 1) {
          const x = right - column;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? this.size - 1 - step : step;
          if (!this.isFixed(x, y) && at < total) {
            this.paint(x, y, (((codewords[at >>> 3] ?? 0) >>> (7 - (at & 7))) & 1) !== 0);
            at += 1;
          }
        }
      }
    }
  }

  applyMask(mask: number): void {
    for (let y = 0; y < this.size; y += 1) {
      for (let x = 0; x < this.size; x += 1) if (!this.isFixed(x, y) && flips(mask, x, y)) this.paint(x, y, !this.isDark(x, y));
    }
  }

  /** The standard's four penalties: long runs, 2 by 2 blocks, finder lookalikes, and dark against light balance. */
  penalty(): number {
    let result = 0;
    const size = this.size;
    for (let y = 0; y < size; y += 1) result += this.linePenalty((at) => this.isDark(at, y));
    for (let x = 0; x < size; x += 1) result += this.linePenalty((at) => this.isDark(x, at));
    for (let y = 0; y < size - 1; y += 1) {
      for (let x = 0; x < size - 1; x += 1) {
        const colour = this.isDark(x, y);
        if (colour === this.isDark(x + 1, y) && colour === this.isDark(x, y + 1) && colour === this.isDark(x + 1, y + 1)) result += PENALTY_N2;
      }
    }
    let dark = 0;
    for (const module of this.dark) if (module) dark += 1;
    const total = size * size;
    const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
    result += k * PENALTY_N4;
    return result;
  }

  /** Runs of five or more alike, and the finder like 1:1:3:1:1 with four light either side, along one line. */
  private linePenalty(at: (index: number) => boolean): number {
    let result = 0;
    let colour = false;
    let run = 0;
    const history = [0, 0, 0, 0, 0, 0, 0];
    const pastRun = (at: number) => history[at] ?? 0;
    const push = (length: number) => {
      // The light border outside the code counts toward the first run.
      if (pastRun(0) === 0) length += this.size;
      history.pop();
      history.unshift(length);
    };
    const count = (): number => {
      const n = pastRun(1);
      const core = n > 0 && pastRun(2) === n && pastRun(3) === n * 3 && pastRun(4) === n && pastRun(5) === n;
      return (core && pastRun(0) >= n * 4 && pastRun(6) >= n ? 1 : 0) + (core && pastRun(6) >= n * 4 && pastRun(0) >= n ? 1 : 0);
    };
    for (let index = 0; index < this.size; index += 1) {
      if (at(index) === colour) {
        run += 1;
        if (run === 5) result += PENALTY_N1;
        else if (run > 5) result += 1;
      } else {
        push(run);
        if (!colour) result += count() * PENALTY_N3;
        colour = at(index);
        run = 1;
      }
    }
    // Close the line as if light modules followed it.
    if (colour) {
      push(run);
      run = 0;
    }
    run += this.size;
    push(run);
    result += count() * PENALTY_N3;
    return result;
  }
}
