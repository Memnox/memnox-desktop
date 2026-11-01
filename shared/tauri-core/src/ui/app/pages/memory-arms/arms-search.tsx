
import { useEffect, useRef } from "react";
import { Search, X } from "lucide-react";

/**
 * The brain's search, a capsule in the middle of the canvas as Rubric draws
 * it: typing dims everything the words do not match and rings what they do,
 * the count says how many, and Enter opens the first.
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
    <div onPointerDown={(event) => event.stopPropagation()} className="pointer-events-none absolute inset-x-0 top-20 z-300 flex justify-center px-4">
      <div className="pointer-events-auto flex w-full max-w-md flex-col items-center gap-1.5">
        <label className="flex w-full items-center gap-2 rounded-full border border-panel-edge bg-card/95 px-4 py-2 shadow-[0_24px_60px_rgb(0_0_0/0.45)] backdrop-blur">
          <Search className="size-4 shrink-0 text-muted" aria-hidden />
          <input
            ref={input}
            type="search"
            aria-label="Search the brain"
            value={query}
            onChange={(event) => onQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && matches > 0) onOpen();
              if (event.key === "Escape") {
                event.stopPropagation();
                onClose();
              }
            }}
            placeholder="SEARCH THE BRAIN"
            className="min-w-0 flex-1 bg-transparent text-body-sm tracking-wide text-foreground placeholder:text-label placeholder:font-semibold placeholder:tracking-[0.2em] placeholder:text-muted focus:outline-none"
          />
          <button type="button" aria-label="Close the search" onClick={onClose} className="rounded-full p-0.5 text-muted hover:text-foreground">
            <X className="size-4" aria-hidden />
          </button>
        </label>
        {asked && (
          <p aria-live="polite" className="rounded-full bg-card/90 px-3 py-0.5 text-label font-semibold tracking-[0.18em] text-muted">
            {matches === 0 ? "NO MATCHES" : `${matches} ${matches === 1 ? "MATCH" : "MATCHES"} · ENTER OPENS`}
          </p>
        )}
      </div>
    </div>
  );
}
