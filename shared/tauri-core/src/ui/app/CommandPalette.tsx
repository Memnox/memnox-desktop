import { CornerDownLeft, Search } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { matchCommands, type Route, type Supports } from '../../core/domain/destinations';
import { shortcutWords } from '../../core/domain/shell-lines';

/** Go to any destination or tab by typing a word of it, then Enter; arrows move, Escape closes, and each destination shows its number key. */
export function CommandPalette({ supports, go, close }: { supports: Supports; go: (route: Route) => void; close: () => void }) {
  const [query, setQuery] = useState('');
  const [at, setAt] = useState(0);
  const field = useRef<HTMLInputElement>(null);
  const found = matchCommands(query, supports);

  useEffect(() => field.current?.focus(), []);
  useEffect(() => setAt(0), [query]);

  const keys = (event: React.KeyboardEvent) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setAt((now) => Math.min(found.length - 1, now + 1));
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      setAt((now) => Math.max(0, now - 1));
    }
    if (event.key === 'Enter') {
      const chosen = found[at];
      if (chosen !== undefined) go(chosen.route);
    }
    if (event.key === 'Escape') close();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/40 px-4 pt-[12vh]" onMouseDown={close} role="presentation">
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Go to"
        className="flex w-full max-w-[560px] flex-col overflow-hidden rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="flex items-center gap-2.5 border-b border-panel-edge px-4">
          <Search size={15} className="text-muted" aria-hidden />
          <input
            ref={field}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={keys}
            placeholder="Go to a page, such as servers or approvals"
            aria-label="Go to"
            className="h-12 flex-1 bg-transparent text-body text-foreground outline-none placeholder:text-faint"
          />
        </div>
        <ul role="listbox" className="max-h-[50vh] overflow-y-auto p-1.5">
          {found.length === 0 && <li className="px-3 py-6 text-center text-footnote text-muted">Nothing here by that name.</li>}
          {found.map((each, index) => (
            <li key={`${each.route.destination}/${each.route.tab ?? ''}`} role="option" aria-selected={index === at}>
              <button
                type="button"
                className={`flex w-full cursor-pointer items-center gap-3 rounded-lg px-3 py-2 text-left text-body ${index === at ? 'bg-hover text-foreground' : 'text-foreground'}`}
                onMouseEnter={() => setAt(index)}
                onClick={() => go(each.route)}
              >
                <span className="flex-1 truncate">{each.title}</span>
                {each.under !== '' && <span className="text-footnote text-muted">{each.under}</span>}
                {each.key !== undefined && <kbd className="rounded border border-panel-edge px-1 font-mono text-micro text-muted">{shortcutWords(each.key, false)}</kbd>}
                {index === at && <CornerDownLeft size={13} className="text-muted" aria-hidden />}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
