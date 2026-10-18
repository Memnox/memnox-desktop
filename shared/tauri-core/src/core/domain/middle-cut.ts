/** What stands for the cut out middle, as the Mac's `truncationMode(.middle)` draws it. */
export const ELLIPSIS = '…';

/**
 * The text cut in the middle until `fits` says it fits, keeping as much of both ends as it can, so a
 * long command keeps its verb and its target. `fits` measures; the caller owns the font.
 */
export function middleCut(text: string, fits: (candidate: string) => boolean): string {
  if (fits(text)) return text;
  const chars = Array.from(text);
  let low = 0;
  let high = chars.length - 1;
  let best = ELLIPSIS;
  // The most characters kept, found by halving, since measuring is the cost.
  while (low <= high) {
    const kept = Math.floor((low + high) / 2);
    const head = Math.ceil(kept / 2);
    const candidate = chars.slice(0, head).join('') + ELLIPSIS + chars.slice(chars.length - (kept - head)).join('');
    if (fits(candidate)) {
      best = candidate;
      low = kept + 1;
    } else {
      high = kept - 1;
    }
  }
  return best;
}
