import { Check, Copy } from 'lucide-react';
import { useEffect, useState } from 'react';
import { tomlLines, type TomlTokenKind } from '../../core/domain/toml-tokens';

/** The console's code colours, as the Mac's CodeColors: table headers orange, keys blue, strings green. */
const TOKEN_CLASS: Record<TomlTokenKind, string> = {
  table: 'text-warm',
  key: 'text-sky',
  string: 'text-success',
  punctuation: 'text-muted',
  comment: 'text-muted',
  plain: 'text-foreground',
};

/** How long Copied stands before the button reads Copy again, long enough to be seen and no longer. */
const COPIED_FOR_MS = 1600;

/**
 * The Mac's CodeBlock: a 40 tall bar naming the file with Copy at its end, a hairline, then the TOML in 12.5 mono
 * with 6 between lines, coloured the console's way, on the page's background inside a 12 radius border.
 */
export function CodeBlock({ code, label, maxHeight, copy }: { code: string; label: string; maxHeight?: number; copy?: (text: string) => Promise<void> }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), COPIED_FOR_MS);
    return () => clearTimeout(timer);
  }, [copied]);
  const press = () => void (copy ?? ((text: string) => navigator.clipboard.writeText(text)))(code).then(() => setCopied(true));
  return (
    <div className="flex flex-col overflow-hidden rounded-xl border border-border bg-background" aria-label={label}>
      <div className="flex h-10 shrink-0 items-center gap-2 pr-2 pl-4">
        <span className="min-w-0 flex-1 truncate text-meta font-medium text-muted">{label}</span>
        <button
          type="button"
          onClick={press}
          title={`Copy ${label}`}
          aria-label={copied ? 'Copied' : `Copy ${label}`}
          className="mx-focus inline-flex h-[26px] cursor-pointer items-center gap-1 rounded-md px-2.5 text-meta font-medium text-muted transition-colors hover:bg-hover hover:text-foreground"
        >
          {copied ? <Check size={11} strokeWidth={2.2} aria-hidden /> : <Copy size={11} strokeWidth={2.2} aria-hidden />}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <div className="h-px shrink-0 bg-border" />
      <pre className="overflow-auto p-4 font-mono text-[12.5px] leading-[21px] select-text" style={maxHeight === undefined ? undefined : { maxHeight }}>
        {tomlLines(code).map((line, row) => (
          <span key={row}>
            {row > 0 && '\n'}
            {line.map((token, at) => (
              <span key={at} className={TOKEN_CLASS[token.kind]}>
                {token.text}
              </span>
            ))}
          </span>
        ))}
      </pre>
    </div>
  );
}
