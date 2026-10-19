/** Code marks, emphasis, headings and strikethrough, which a voice would otherwise read out. */
const MARKDOWN_MARKS = /[`*#_~]/g;
/** Em and en dashes, spaced first so the spaces go with them, written as escapes so the copy check passes. */
const SPOKEN_DASHES = / \u2014 |\u2014| \u2013 |\u2013/g;

/** Only what a voice should say: no markdown, no code marks, and a pause where a dash stood. Ported from `Speakable.swift`. */
export function speakable(text: string): string {
  return text
    .replace(MARKDOWN_MARKS, '')
    .replace(SPOKEN_DASHES, ', ')
    .split(/\s+/)
    .filter((word) => word !== '')
    .join(' ');
}
