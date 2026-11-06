import type { ReactNode } from 'react';
import { ALL_CATEGORIES, showingLine, type CategoryCount } from '../../core/domain/catalog';
import { SearchField } from '../settings/kit';

/**
 * The console's Connected tools page in parts, so every catalogue in this window reads the same: tabs with
 * counts across the top, categories down the side, a search with "N of M" beside it, then the cards.
 */

export interface PageTab {
  readonly id: string;
  readonly title: string;
  /** Left out where the shell has nothing to count, as on the tabs of a sidebar row. */
  readonly count?: number;
}

/** Tabs as the console's page tabs: an underline under the chosen one, its count in mono beside its name. */
export function PageTabs({ tabs, chosen, choose, label }: { tabs: readonly PageTab[]; chosen: string; choose: (id: string) => void; label: string }) {
  return (
    <div role="tablist" aria-label={label} className="flex flex-wrap gap-x-5 border-b border-panel-edge">
      {tabs.map((tab) => {
        const on = tab.id === chosen;
        return (
          <button
            key={tab.id}
            type="button"
            role="tab"
            aria-selected={on}
            onClick={() => choose(tab.id)}
            className={`mx-focus -mb-px flex h-9 cursor-pointer items-center gap-1.5 border-b-2 text-body-sm ${on ? 'border-primary font-medium text-foreground' : 'border-transparent text-muted hover:text-foreground'}`}
          >
            {tab.title}
            {tab.count !== undefined && <span className="font-mono text-label tabular-nums text-muted">{tab.count}</span>}
          </button>
        );
      })}
    </div>
  );
}

/** The categories down the side with their counts, All first; a select in its place where the window is narrow. */
export function CategoryRail({ categories, total, chosen, choose, allTitle }: { categories: readonly CategoryCount[]; total: number; chosen: string; choose: (id: string) => void; allTitle: string }) {
  const rows = [{ id: ALL_CATEGORIES, title: allTitle, count: total }, ...categories];
  return (
    <>
      <nav aria-label="Categories" className="hidden min-[900px]:block">
        <p className="mb-2 px-2.5 font-mono text-label tracking-[0.14em] text-muted uppercase">Categories</p>
        <ul className="flex flex-col gap-0.5">
          {rows.map((row) => (
            <li key={row.id}>
              <button
                type="button"
                onClick={() => choose(row.id)}
                aria-current={row.id === chosen ? 'true' : undefined}
                className={`mx-focus flex w-full cursor-pointer items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-body-sm ${row.id === chosen ? 'bg-hover font-medium text-foreground' : 'text-muted hover:bg-hover hover:text-foreground'}`}
              >
                <span className="min-w-0 flex-1 truncate">{row.title}</span>
                <span className="shrink-0 font-mono text-label tabular-nums">{row.count}</span>
              </button>
            </li>
          ))}
        </ul>
      </nav>
      <select
        aria-label="Category"
        value={chosen}
        onChange={(event) => choose(event.target.value)}
        className="mx-field h-9 rounded-lg border border-field-edge bg-field px-3 text-body-sm text-foreground min-[900px]:hidden"
      >
        {rows.map((row) => (
          <option key={row.id} value={row.id}>{`${row.title} (${row.count})`}</option>
        ))}
      </select>
    </>
  );
}

/** The search, and how much of the pool is on screen beside it. */
export function CatalogSearch({ value, placeholder, showing, total, onChange }: { value: string; placeholder: string; showing: number; total: number; onChange: (value: string) => void }) {
  return (
    <div className="flex items-center gap-3">
      <div className="min-w-0 flex-1">
        <SearchField value={value} placeholder={placeholder} onChange={onChange} />
      </div>
      <p className="shrink-0 font-mono text-label tabular-nums text-muted" aria-live="polite">
        {showingLine(showing, total)}
      </p>
    </div>
  );
}

/** The rail beside the search and the cards, stacking under 900 where a column would push the cards off the fold. */
export function CatalogLayout({ rail, children }: { rail: ReactNode; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-x-6 gap-y-3 min-[900px]:grid-cols-[11rem_minmax(0,1fr)]">
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
        <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-hover text-muted">{icon}</span>
        <span className="line-clamp-2 min-w-0 flex-1 text-body-sm font-medium text-foreground">{title}</span>
      </div>
      <p className="line-clamp-2 flex-1 text-meta text-muted" title={line}>
        {line}
      </p>
      <div className="flex flex-wrap items-center gap-1.5">{badges}</div>
    </>
  );
  const frame = `flex min-w-0 flex-col gap-3 rounded-xl border bg-card p-4 text-left ${chosen ? 'border-primary' : 'border-panel-edge'}`;
  return (
    <div className={frame}>
      {onClick === undefined ? (
        body
      ) : (
        <button type="button" onClick={onClick} aria-pressed={chosen} className="mx-focus flex flex-1 cursor-pointer flex-col gap-3 rounded-lg text-left">
          {body}
        </button>
      )}
      {action !== undefined && <div className="flex items-center justify-end gap-1.5">{action}</div>}
      {more}
    </div>
  );
}
