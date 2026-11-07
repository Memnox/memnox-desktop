/**
 * Which names the brain prints, decided in screen pixels: greedily by weight,
 * so a hub's name wins over a piece's, and a label that would lie over one
 * already placed is left off rather than drawn into a pile. A label marked
 * `always` is placed whatever it covers, which is what the hovered name is.
 */

export type LabelBox = {
  id: string;
  /** The box's top left corner and size, in screen pixels. */
  left: number;
  top: number;
  width: number;
  height: number;
  weight: number;
  always?: boolean;
};

/** The room kept clear round every placed label. */
const PAD = 2;
/** The grid the placed boxes are filed in, so a check reads only its neighbours. */
const CELL = 96;

export function placeLabels(boxes: readonly LabelBox[], pad: number = PAD): Set<string> {
  const ordered = [...boxes].sort(
    (a, b) => Number(b.always === true) - Number(a.always === true) || b.weight - a.weight || a.id.localeCompare(b.id),
  );
  const grid = new Map<string, LabelBox[]>();
  const shown = new Set<string>();
  for (const box of ordered) {
    const cells = cellsOf(box, pad);
    const clear = box.always === true || cells.every((cell) => (grid.get(cell) ?? []).every((other) => !overlaps(box, other, pad)));
    if (!clear) continue;
    shown.add(box.id);
    for (const cell of cells) grid.set(cell, [...(grid.get(cell) ?? []), box]);
  }
  return shown;
}

function overlaps(a: LabelBox, b: LabelBox, pad: number): boolean {
  return a.left < b.left + b.width + pad && b.left < a.left + a.width + pad && a.top < b.top + b.height + pad && b.top < a.top + a.height + pad;
}

function cellsOf(box: LabelBox, pad: number): string[] {
  const cells: string[] = [];
  const fromX = Math.floor((box.left - pad) / CELL);
  const toX = Math.floor((box.left + box.width + pad) / CELL);
  const fromY = Math.floor((box.top - pad) / CELL);
  const toY = Math.floor((box.top + box.height + pad) / CELL);
  for (let x = fromX; x <= toX; x += 1) for (let y = fromY; y <= toY; y += 1) cells.push(`${x}:${y}`);
  return cells;
}

/** A name cut to fit a label, with an ellipsis where it was cut. */
export function clipped(text: string, most: number): string {
  return text.length <= most ? text : `${text.slice(0, Math.max(1, most - 1)).trimEnd()}…`;
}
