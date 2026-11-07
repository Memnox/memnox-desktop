
import { useEffect, useRef } from "react";
import { Search, X } from "lucide-react";
import { Input, Pressable } from "../../../kit";
import { ArmsLines } from "../../../../core/domain/memory-brain-lines";

/** The magnifier and the close mark, at the size of the capsule's meta words. */
const SEEK_GLYPH = 13;

/**
 * The brain's search, a capsule centred over the brain as the Mac's `BrainSeek` draws it: typing dims everything the
 * words do not match and rings what they do, the count says how many, Enter opens the best and Escape puts it away.
 */
export function ArmsSearch({
  query,
  onQuery,
  matches,
  onOpen,
  onClose,
}: {
  query: string;
  onQuery: (query: string) => void;
  matches: number;
  onOpen: () => void;
  onClose: () => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => input.current?.focus(), []);
  const asked = query.trim() !== "";

  return (
    <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-none absolute inset-x-0 top-brain-seek-top z-300 flex justify-center px-4">
      <div className="pointer-events-auto flex flex-col items-center gap-1.5">
        <label className="flex h-control w-brain-seek max-w-full items-center gap-2 rounded-full border border-panel-edge bg-brain-panel px-3">
          <Search size={SEEK_GLYPH} className="shrink-0 text-muted" aria-hidden />
          <Input
            ref={input}
            look="bare"
            type="search"
            aria-label={ArmsLines.search}
            value={query}
            onValue={onQuery}
            onKeyDown={(event) => {
              if (event.key === "Enter" && matches > 0) onOpen();
              if (event.key === "Escape") {
                event.stopPropagation();
                onClose();
              }
            }}
            placeholder={ArmsLines.searchPlaceholder}
            className="min-w-0 flex-1 font-code text-meta font-medium tracking-heading text-foreground placeholder:text-faint focus:outline-none"
          />
          <Pressable aria-label={ArmsLines.closeSearch} onClick={onClose} className="shrink-0 cursor-pointer text-muted">
            <X size={SEEK_GLYPH} aria-hidden />
          </Pressable>
        </label>
        {asked && (
          <p aria-live="polite" className={`font-code text-brain-caption font-medium tracking-heading ${matches > 0 ? "text-muted" : "text-faint"}`}>
            {matches === 0 ? ArmsLines.noMatches : ArmsLines.matches(matches)}
          </p>
        )}
      </div>
    </div>
  );
}
