/**
 * Base64 and base64url, and UTF-8 out of bytes, by hand, since the core runs with no DOM and no Node. Base64url is
 * written without padding, the way remote-contract.md writes mailbox ids, the pairing link and fingerprints.
 * Ported from the Mac's `Base64URL`.
 */
const STANDARD = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const URL_SAFE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function decodeWith(alphabet: string, text: string): Uint8Array | undefined {
  const body = text.replace(/=+$/, '');
  // One character left over is never a whole byte, so it is not base64 at all.
  if (body.length % 4 === 1) return undefined;
  const bytes: number[] = [];
  let bits = 0;
  let value = 0;
  for (const character of body) {
    const digit = alphabet.indexOf(character);
    if (digit === -1) return undefined;
    value = (value << 6) | digit;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((value >> bits) & 0xff);
    }
  }
  return Uint8Array.from(bytes);
}

function encodeWith(alphabet: string, bytes: Uint8Array): string {
  let text = '';
  let bits = 0;
  let value = 0;
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      text += alphabet[(value >> bits) & 0x3f];
    }
  }
  if (bits > 0) text += alphabet[(value << (6 - bits)) & 0x3f];
  return text;
}

export const Base64URL = {
  encode: (bytes: Uint8Array): string => encodeWith(URL_SAFE, bytes),
  /** Undefined for anything that is not base64url, padded or not. */
  decode: (text: string): Uint8Array | undefined => decodeWith(URL_SAFE, text),
};

/** Standard base64, undefined for anything else. */
export function fromBase64(text: string): Uint8Array | undefined {
  return decodeWith(STANDARD, text);
}

/** UTF-8 bytes as text, a replacement character for anything malformed. */
export function utf8(bytes: Uint8Array): string {
  let text = '';
  for (let at = 0; at < bytes.length; ) {
    const first = bytes[at] ?? 0;
    const length = first < 0x80 ? 1 : first >> 5 === 0b110 ? 2 : first >> 4 === 0b1110 ? 3 : first >> 3 === 0b11110 ? 4 : 0;
    if (length === 0 || at + length > bytes.length) {
      text += '�';
      at += 1;
      continue;
    }
    let point = length === 1 ? first : first & (0xff >> (length + 1));
    for (let index = 1; index < length; index += 1) point = (point << 6) | ((bytes[at + index] ?? 0) & 0x3f);
    text += String.fromCodePoint(point);
    at += length;
  }
  return text;
}
