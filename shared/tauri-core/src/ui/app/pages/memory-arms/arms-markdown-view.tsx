import { markdownBlocks, type Block, type Inline } from "../../../../core/domain/memory-arms/arms-markdown";

/** A skill's instructions, formatted, in the console's type scale. */
export function MarkdownView({ source }: { source: string }) {
  const blocks = markdownBlocks(source);
  return (
    <div className="flex flex-col gap-2 text-body-sm leading-relaxed text-foreground">
      {blocks.map((block, at) => (
        <BlockView key={at} block={block} />
      ))}
    </div>
  );
}

const HEADING_CLASS = ["text-body font-semibold", "text-body-sm font-semibold", "text-body-sm font-medium"];

function BlockView({ block }: { block: Block }) {
  switch (block.kind) {
    case "heading":
      return (
        <p className={`mt-1 ${HEADING_CLASS[Math.min(block.level, 3) - 1]}`}>
          <Inlines inline={block.inline} />
        </p>
      );
    case "list": {
      const List = block.ordered ? "ol" : "ul";
      return (
        <List className={`flex flex-col gap-0.5 pl-5 ${block.ordered ? "list-decimal" : "list-disc"}`}>
          {block.items.map((item, at) => (
            <li key={at}>
              <Inlines inline={item} />
            </li>
          ))}
        </List>
      );
    }
    case "quote":
      return (
        <p className="border-l-2 border-panel-edge pl-3 text-muted">
          <Inlines inline={block.inline} />
        </p>
      );
    case "code":
      return <pre className="overflow-x-auto rounded-md bg-hover px-3 py-2 text-meta">{block.text}</pre>;
    case "paragraph":
      return (
        <p>
          <Inlines inline={block.inline} />
        </p>
      );
  }
}

function Inlines({ inline }: { inline: Inline[] }) {
  return (
    <>
      {inline.map((part, at) => {
        switch (part.kind) {
          case "text":
            return <span key={at}>{part.text}</span>;
          case "code":
            return (
              <code key={at} className="rounded bg-hover px-1 py-0.5 text-meta">
                {part.text}
              </code>
            );
          case "strong":
            return (
              <strong key={at} className="font-semibold">
                {part.text}
              </strong>
            );
          case "em":
            return <em key={at}>{part.text}</em>;
          case "link":
            return (
              <a key={at} href={part.href} target="_blank" rel="noreferrer" className="text-primary hover:underline">
                {part.text}
              </a>
            );
        }
      })}
    </>
  );
}
