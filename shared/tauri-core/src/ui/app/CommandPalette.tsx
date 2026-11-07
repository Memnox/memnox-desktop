import { CornerDownLeft, Search } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { matchCommands, type Route, type Supports } from '../../core/domain/destinations';
import { PaletteLines, shortcutWords } from '../../core/domain/shell-lines';
import { Input, Modal, Pressable } from '../kit';

/** The magnifier beside the palette's field and the return mark on the row Enter would open. */
const SEARCH_GLYPH = 15;
const ENTER_GLYPH = 13;

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
  };

  return (
    <Modal label={PaletteLines.label} close={close} place="palette">
      <div className="flex items-center gap-2.5 border-b border-panel-edge px-4">
        <Search size={SEARCH_GLYPH} className="text-muted" aria-hidden />
        <Input
          ref={field}
          look="bare"
          value={query}
          onValue={setQuery}
          onKeyDown={keys}
          placeholder={PaletteLines.prompt}
          aria-label={PaletteLines.label}
          className="h-12 flex-1 text-body text-foreground placeholder:text-faint"
        />
      </div>
      <ul role="listbox" className="max-h-[50vh] overflow-y-auto p-1.5">
        {found.length === 0 && <li className="px-3 py-6 text-center text-footnote text-muted">{PaletteLines.nothing}</li>}
        {found.map((each, index) => (
          <li key={`${each.route.destination}/${each.route.tab ?? ''}`} role="option" aria-selected={index === at}>
            <Pressable
              className={`flex w-full cursor-pointer items-center gap-3 rounded-control px-3 py-2 text-left text-body text-foreground ${index === at ? 'bg-hover' : ''}`}
              onMouseEnter={() => setAt(index)}
              onClick={() => go(each.route)}
            >
              <span className="flex-1 truncate">{each.title}</span>
              {each.under !== '' && <span className="text-footnote text-muted">{each.under}</span>}
              {each.key !== undefined && <kbd className="rounded-key border border-panel-edge px-1 font-code text-micro text-muted">{shortcutWords(each.key, false)}</kbd>}
              {index === at && <CornerDownLeft size={ENTER_GLYPH} className="text-muted" aria-hidden />}
            </Pressable>
          </li>
        ))}
      </ul>
    </Modal>
  );
}
