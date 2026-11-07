/**
 * The Mac's own stable fraction for an id (`SurfaceOrbit.unit`), so a cluster
 * packed here lands where the Mac packs it. The Mac runs FNV 1a over 64 bits
 * and keeps the low twenty; a product's low bits depend only on the low bits
 * of what was multiplied, so the same twenty bits come out of plain 32 bit
 * arithmetic with no BigInt.
 */

const FRACTION_BITS = 20;
const FRACTION = 2 ** FRACTION_BITS;
const MASK = FRACTION - 1;
/** The low twenty bits of FNV's 64 bit offset basis 0xcbf29ce484222325 and of its prime 0x100000001b3. */
const BASIS_LOW = 0x22325;
const PRIME_LOW = 0x1b3;

/** The text as UTF 8 bytes, written out here since the core has no TextEncoder, so a name hashes as the Mac hashes it. */
function utf8(text: string): number[] {
  const bytes: number[] = [];
  for (const char of text) {
    const code = char.codePointAt(0) ?? 0;
    if (code < 0x80) bytes.push(code);
    else if (code < 0x800) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    else if (code < 0x10000) bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    else bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
  }
  return bytes;
}

/** A fraction from 0 to under 1 drawn from an id and a salt, the same on every load and on the Mac. */
export function stableUnit(id: string, salt: number): number {
  let hash = (BASIS_LOW ^ (salt & MASK)) & MASK;
  for (const byte of utf8(id)) {
    hash ^= byte;
    hash = Math.imul(hash, PRIME_LOW) & MASK;
  }
  return hash / FRACTION;
}

/** The salts the brain draws with, numbered as the Mac's `BrainArms` numbers its own. */
export const SALT = {
  angle: 71,
  ring: 72,
  latitude: 73,
  cluster: 51,
  order: 52,
} as const;
