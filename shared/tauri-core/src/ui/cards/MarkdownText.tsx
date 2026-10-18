import { Fragment } from 'react';
import { inlineMarks, isOpenableLink, markdownBlocks, type InlineRun } from '../../core/domain/markdown';

/** The system monospaced face, which `.system(design: .monospaced)` always is. */
export const SYSTEM_MONO = "font-[ui-monospace,'SF_Mono','Cascadia_Mono','JetBrains_Mono',Consolas,monospace]";

/**
 * `MarkdownText`: a card's markdown laid out as written, 6 between blocks, in the foreground at 92%.
 * Headings 15 semibold, bullets 13 behind a blue dot, code 11.5 mono on black 28%, paragraphs 13.5,
 * with backticks, bold, italics and links drawn inside each line. `tone` picks the island's near white
 * or a window's adaptive foreground.
 */
export function MarkdownText({ source, tone = 'island', onLink, className }: { source: string; tone?: 'island' | 'window'; onLink?: (href: string) => void; className?: string }) {
  const ink = tone === 'island' ? 'text-white/[0.92]' : 'text-foreground/[0.92]';
  const strong = tone === 'island' ? 'text-white' : 'text-foreground';
  return (
    <div className={`flex flex-col gap-1.5 select-text ${ink} ${className ?? ''}`}>
      {markdownBlocks(source).map((block, index) => {
        switch (block.kind) {
          case 'heading':
            return (
              <p key={index} className={`m-0 pt-0.5 text-headline font-semibold ${strong}`}>
                <Inline line={block.text} onLink={onLink} />
              </p>
            );
          case 'bullet':
            return (
              <div key={index} className="flex items-baseline gap-[7px] text-body leading-[18px]">
                <span className="font-semibold text-primary">{'•'}</span>
                <span className="min-w-0">
                  <Inline line={block.text} onLink={onLink} />
                </span>
              </div>
            );
          case 'code':
            return (
              <pre key={index} className={`m-0 w-full overflow-x-auto whitespace-pre rounded-control bg-black/[0.28] p-2 text-[11.5px] leading-[15px] ${SYSTEM_MONO}`}>
                {block.text}
              </pre>
            );
          case 'text':
            return (
              <p key={index} className="m-0 text-[13.5px] leading-[19.5px]">
                <Inline line={block.text} onLink={onLink} />
              </p>
            );
        }
      })}
    </div>
  );
}

/** One line with its inline marks, whitespace kept as written. */
function Inline({ line, onLink }: { line: string; onLink?: (href: string) => void }) {
  return (
    <>
      {inlineMarks(line).map((run, index) => (
        <Fragment key={index}>{runOf(run, onLink)}</Fragment>
      ))}
    </>
  );
}

function runOf(run: InlineRun, onLink: ((href: string) => void) | undefined) {
  switch (run.kind) {
    case 'plain':
      return <span className="whitespace-pre-wrap">{run.text}</span>;
    case 'code':
      return <code className={`rounded-key bg-white/[0.08] px-1 py-px text-[0.9em] ${SYSTEM_MONO}`}>{run.text}</code>;
    case 'strong':
      return <strong className="font-semibold">{run.text}</strong>;
    case 'emphasis':
      return <em>{run.text}</em>;
    case 'link':
      return isOpenableLink(run.href) ? (
        <a
          href={run.href}
          className="cursor-pointer text-primary underline-offset-2 hover:underline"
          onClick={(event) => {
            event.preventDefault();
            onLink?.(run.href);
          }}
        >
          {run.text}
        </a>
      ) : (
        <span>{run.text}</span>
      );
  }
}
