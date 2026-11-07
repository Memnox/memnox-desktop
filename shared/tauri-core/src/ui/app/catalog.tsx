import type { ReactNode } from 'react';
import { ALL_CATEGORIES, CatalogLines, type CategoryCount } from '../../core/domain/catalog';
import { Card, Chip, ChipGroup, Pressable } from '../kit';

/**
 * The console's Connected tools page in parts, so every catalogue in this window reads the same: tabs with
 * counts across the top, categories down the side, a search with "N of M" beside it, then the cards.
 */

/**
 * `CategoryRail`: a heading in the code face, 12 uppercase spaced 1.98, then All and each category 10 across and 6
 * down, 2 apart, the chosen one 13 medium on the active fill and its count 12 faint in the code face. Chips take its
 * place where the window is narrow, as on the Mac.
 */
export function CategoryRail({ categories, total, chosen, choose, allTitle }: { categories: readonly CategoryCount[]; total: number; chosen: string; choose: (id: string) => void; allTitle: string }) {
  const rows = [{ id: ALL_CATEGORIES, title: allTitle, count: total }, ...categories];
  return (
    <>
      <nav aria-label={CatalogLines.categories} className="hidden flex-col gap-0.5 medium:flex">
        <p className="px-2.5 pb-1.5 font-code text-meta tracking-heading text-muted uppercase">{CatalogLines.categories}</p>
        {rows.map((row) => {
          const on = row.id === chosen;
          return (
            <Pressable
              key={row.id}
              onClick={() => choose(row.id)}
              aria-current={on ? 'true' : undefined}
              className={`mx-focus flex w-full cursor-pointer items-center gap-1.5 rounded-control px-2.5 py-1.5 text-left text-body-sm ${on ? 'bg-active font-medium text-foreground' : 'text-muted'}`}
            >
              <span className="min-w-0 flex-1 truncate">{row.title}</span>
              <span className="shrink-0 font-code text-meta tabular-nums text-faint">{row.count}</span>
            </Pressable>
          );
        })}
      </nav>
      {/* Chips above the cards where the window is too narrow for the rail, as the Mac folds it. */}
      <ChipGroup label={CatalogLines.categories} role="group" className="medium:hidden">
        {rows.map((row) => (
          <Chip key={row.id} on={row.id === chosen} pick={() => choose(row.id)} role="toggle" count={row.count}>
            {row.title}
          </Chip>
        ))}
      </ChipGroup>
    </>
  );
}

/** The rail beside the search and the cards, stacking under 900 where a column would push the cards off the fold. */
export function CatalogLayout({ rail, children }: { rail: ReactNode; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-x-6 gap-y-3 medium:grid-cols-(--mx-shell-catalog-columns)">
      <div>{rail}</div>
      <div className="flex min-w-0 flex-col gap-3">{children}</div>
    </div>
  );
}

/** One card: an icon, a title, one line, the badges, its action at the foot, and anything folded under it. */
export function CatalogCard({
  icon,
  title,
  line,
  badges,
  action,
  more,
  chosen = false,
  onClick,
}: {
  icon: ReactNode;
  title: string;
  line: string;
  badges: ReactNode;
  action?: ReactNode;
  /** Drawn under the press rather than in it, so a disclosure there opens without picking the card. */
  more?: ReactNode;
  chosen?: boolean;
  onClick?: () => void;
}) {
  const body = (
    <>
      <div className="flex min-w-0 items-start gap-3">
        <span className="grid size-control shrink-0 place-items-center rounded-control bg-hover text-muted">{icon}</span>
        <span className="line-clamp-2 min-w-0 flex-1 text-body-sm font-medium text-foreground">{title}</span>
      </div>
      <p className="line-clamp-2 flex-1 text-meta text-muted" title={line}>
        {line}
      </p>
      <div className="flex flex-wrap items-center gap-1.5">{badges}</div>
    </>
  );
  return (
    <Card chosen={chosen} className="flex min-w-0 flex-col gap-3 text-left">
      {onClick === undefined ? (
        body
      ) : (
        <Pressable onClick={onClick} aria-pressed={chosen} className="mx-focus flex flex-1 cursor-pointer flex-col gap-3 rounded-control text-left">
          {body}
        </Pressable>
      )}
      {action !== undefined && <div className="flex items-center justify-end gap-1.5">{action}</div>}
      {more}
    </Card>
  );
}
