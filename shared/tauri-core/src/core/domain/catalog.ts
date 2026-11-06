/**
 * The one page shape every Memnox surface shares, after the console's Connected tools page: tabs with counts,
 * categories down the side, a search that says how much of the whole is on screen, and a grid of cards.
 * These are its rules, pure, so the Rules page and any later page count and narrow alike.
 */

/** Stands for every category, so the rail's first row is never confused with a real one. */
export const ALL_CATEGORIES = 'all';

export interface CategoryCount {
  readonly id: string;
  readonly title: string;
  readonly count: number;
}

/** "3 of 12", the console's line beside its search, since a filter has to say what it hid. */
export function showingLine(showing: number, total: number): string {
  return `${showing} of ${total}`;
}

/** The words typed, lower cased and split, so an empty search matches everything. */
export function searchWords(query: string): readonly string[] {
  return query.trim().toLowerCase().split(/\s+/).filter((word) => word !== '');
}

/** Whether every word typed is somewhere in the item's text, in any order. */
export function matchesSearch(words: readonly string[], text: string): boolean {
  const haystack = text.toLowerCase();
  return words.every((word) => haystack.includes(word));
}

/**
 * The categories the items fall into, in the order the page names them, each with its count, a category
 * nothing falls into left out so the rail never offers an empty shelf.
 */
export function categoryCounts<T>(items: readonly T[], categoryOf: (item: T) => string, order: readonly { id: string; title: string }[]): CategoryCount[] {
  const counts = new Map<string, number>();
  for (const item of items) counts.set(categoryOf(item), (counts.get(categoryOf(item)) ?? 0) + 1);
  return order.flatMap((each) => {
    const count = counts.get(each.id) ?? 0;
    return count === 0 ? [] : [{ id: each.id, title: each.title, count }];
  });
}

/** A category chosen on one tab may hold nothing on the next, so it falls back to all rather than an empty grid. */
export function settledCategory(chosen: string, counts: readonly CategoryCount[]): string {
  return chosen === ALL_CATEGORIES || counts.some((each) => each.id === chosen) ? chosen : ALL_CATEGORIES;
}
