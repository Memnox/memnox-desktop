import { describe, expect, it } from 'vitest';
import { formatBits, qrModules, qrPath, qrSize, reedSolomonRemainder, withErrorCorrection } from '../src/core/domain/qr';

const PAIR_LINK = `memnox://pair?d=${'eyJ2IjoxLCJtYWNoaW5lSWQiOiJtY2hfMDFKOUFCQ0RFRiIsIm1hY2hpbmUiOiJTYW0ncyBQQyIsInJlbGF5VXJsIjoid3NzOi8vcmVsYXkubWVtbm94LmNvbSJ9'.repeat(3)}`.slice(0, 300);

/** One module, light when out of range, so reading the grid needs no checks. */
const cell = (m: boolean[][], x: number, y: number): boolean => m[y]?.[x] === true;

/** Version from a square's side. */
const versionOf = (modules: boolean[][]) => (modules.length - 17) / 4;

/** The 15 format bits as drawn around the top left finder, least significant first. */
function formatAroundTopLeft(m: boolean[][]): number {
  const at = (x: number, y: number) => (cell(m, x, y) ? 1 : 0);
  const bits: number[] = [];
  for (let i = 0; i <= 5; i += 1) bits.push(at(8, i));
  bits.push(at(8, 7), at(8, 8), at(7, 8));
  for (let i = 9; i < 15; i += 1) bits.push(at(14 - i, 8));
  return bits.reduce((sum, bit, i) => sum | (bit << i), 0);
}

/** The same bits as split between the other two finders. */
function formatSplit(m: boolean[][]): number {
  const size = m.length;
  const at = (x: number, y: number) => (cell(m, x, y) ? 1 : 0);
  const bits: number[] = [];
  for (let i = 0; i < 8; i += 1) bits.push(at(size - 1 - i, 8));
  for (let i = 8; i < 15; i += 1) bits.push(at(8, size - 15 + i));
  return bits.reduce((sum, bit, i) => sum | (bit << i), 0);
}

function hasFinder(m: boolean[][], left: number, top: number): boolean {
  for (let dy = 0; dy < 7; dy += 1) {
    for (let dx = 0; dx < 7; dx += 1) {
      const ring = Math.max(Math.abs(dx - 3), Math.abs(dy - 3));
      if (cell(m, left + dx, top + dy) !== (ring !== 2)) return false;
    }
  }
  return true;
}

describe('qrModules', () => {
  it('picks the smallest version that holds the bytes', () => {
    expect(qrModules('HELLO WORLD').length).toBe(21);
    // Version 1 at M holds 14 bytes, version 2 holds 26.
    expect(versionOf(qrModules('a'.repeat(14)))).toBe(1);
    expect(versionOf(qrModules('a'.repeat(15)))).toBe(2);
    // 100 bytes: version 5 at M holds 84, version 6 holds 106.
    expect(versionOf(qrModules('x'.repeat(100)))).toBe(6);
    // 300 bytes: version 11 at M holds 251 and version 12 holds 287, so 13 (331).
    expect(PAIR_LINK.length).toBe(300);
    expect(versionOf(qrModules(PAIR_LINK))).toBe(13);
    // Level L packs more in: 100 bytes fit version 5 (106).
    expect(versionOf(qrModules('x'.repeat(100), 'L'))).toBe(5);
  });

  it('counts UTF-8 bytes rather than characters', () => {
    // Seven two byte letters are 14 bytes, eight are 16.
    expect(versionOf(qrModules('é'.repeat(7)))).toBe(1);
    expect(versionOf(qrModules('é'.repeat(8)))).toBe(2);
  });

  it('refuses what no version holds', () => {
    expect(() => qrModules('x'.repeat(3000))).toThrow(RangeError);
  });

  it('draws the three finders, the timing lines and the dark module', () => {
    for (const text of ['HELLO WORLD', PAIR_LINK]) {
      const m = qrModules(text);
      const size = m.length;
      expect(hasFinder(m, 0, 0)).toBe(true);
      expect(hasFinder(m, size - 7, 0)).toBe(true);
      expect(hasFinder(m, 0, size - 7)).toBe(true);
      for (let at = 8; at < size - 8; at += 1) {
        expect(cell(m, at, 6)).toBe(at % 2 === 0);
        expect(cell(m, 6, at)).toBe(at % 2 === 0);
      }
      expect(cell(m, 8, size - 8)).toBe(true);
    }
  });

  it('writes valid format bits for its level and mask, the same in both places', () => {
    for (const level of ['L', 'M', 'Q', 'H'] as const) {
      const m = qrModules(PAIR_LINK.slice(0, 40), level);
      const drawn = formatAroundTopLeft(m);
      expect(formatSplit(m)).toBe(drawn);
      const masks = [0, 1, 2, 3, 4, 5, 6, 7].filter((mask) => formatBits(level, mask) === drawn);
      expect(masks).toHaveLength(1);
    }
  });

  it('knows the standard format words', () => {
    // From the standard's table: M with mask 0, L with mask 7, H with mask 0.
    expect(formatBits('M', 0)).toBe(0b101010000010010);
    expect(formatBits('L', 7)).toBe(0b110100101110110);
    expect(formatBits('H', 0)).toBe(0b001011010001001);
  });

  it('writes the version information from version 7', () => {
    const m = qrModules('x'.repeat(200));
    const version = versionOf(m);
    expect(version).toBeGreaterThanOrEqual(7);
    const size = m.length;
    let bits = 0;
    for (let at = 0; at < 18; at += 1) {
      const a = size - 11 + (at % 3);
      const b = Math.floor(at / 3);
      expect(cell(m, a, b)).toBe(cell(m, b, a));
      if (cell(m, a, b)) bits |= 1 << at;
    }
    expect(bits >>> 12).toBe(version);
  });
});

describe('Reed Solomon', () => {
  it('gives the textbook correction for HELLO WORLD at version 1 M', () => {
    // The worked example: "HELLO WORLD" in alphanumeric mode at 1 M, with its ten correction codewords.
    const data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
    const codewords = withErrorCorrection(data, 1, 'M');
    expect(codewords.slice(0, 16)).toEqual(data);
    expect(codewords.slice(16)).toEqual([196, 35, 39, 119, 235, 215, 231, 226, 93, 23]);
  });

  it('leaves every block a codeword that vanishes at the generator roots', () => {
    // Version 5 Q has two blocks of 15 and two of 16, the uneven case interleaving has to get right.
    const data = Array.from({ length: 62 }, (_, i) => (i * 37 + 11) & 0xff);
    const stream = withErrorCorrection(data, 5, 'Q');
    expect(stream).toHaveLength(134);
    const lengths = [15, 15, 16, 16];
    const blocks: number[][] = lengths.map(() => []);
    let at = 0;
    for (let i = 0; i < 16; i += 1) {
      lengths.forEach((length, b) => {
        if (i < length) blocks[b]?.push(stream[at++] ?? -1);
      });
    }
    expect(blocks.flat()).toEqual(data);
    for (let i = 0; i < 18; i += 1) for (const block of blocks) block.push(stream[at++] ?? -1);
    // An independent field by log tables, so the check shares no code with the encoder.
    const exp: number[] = [];
    const log: number[] = [];
    for (let i = 0, x = 1; i < 255; i += 1, x = x & 0x80 ? ((x << 1) ^ 0x11d) & 0xff : x << 1) {
      exp[i] = x;
      log[x] = i;
    }
    const mul = (a: number, b: number) => (a === 0 || b === 0 ? 0 : (exp[((log[a] ?? 0) + (log[b] ?? 0)) % 255] ?? 0));
    for (const block of blocks) {
      for (let root = 0; root < 18; root += 1) {
        const value = block.reduce((sum, coefficient) => mul(sum, exp[root] ?? 0) ^ coefficient, 0);
        expect(value).toBe(0);
      }
    }
    expect(reedSolomonRemainder([], [1, 2, 3])).toEqual([0, 0, 0]);
  });
});

describe('qrPath', () => {
  it('draws each run of dark modules as one rectangle', () => {
    expect(qrPath([[true, true, false, true]])).toBe('M0 0h2v1h-2zM3 0h1v1h-1z');
    expect(qrPath([[false], [true]])).toBe('M0 1h1v1h-1z');
  });

  it('covers exactly the dark modules of a real code', () => {
    const m = qrModules('HELLO WORLD');
    const dark = m.flat().filter(Boolean).length;
    const covered = [...qrPath(m).matchAll(/h(\d+)v1/g)].reduce((sum, match) => sum + Number(match[1]), 0);
    expect(covered).toBe(dark);
    expect(qrSize(1)).toBe(21);
  });
});
