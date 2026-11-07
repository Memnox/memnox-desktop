import { describe, expect, it } from "vitest";

import { inlineOf, markdownBlocks } from "../src/core/domain/memory-arms/arms-markdown";

describe("a skill's markdown", () => {
  it("reads headings, lists, code and paragraphs as blocks, past the front matter", () => {
    const blocks = markdownBlocks(["---", "name: review", "---", "# Review", "", "Read the diff.", "", "- one", "- two", "", "```", "git diff", "```"].join("\n"));
    expect(blocks.map((block) => block.kind)).toEqual(["heading", "paragraph", "list", "code"]);
    const list = blocks[2];
    expect(list?.kind === "list" ? list.items.length : 0).toBe(2);
  });

  it("keeps inline code, bold and emphasis apart from the words around them", () => {
    expect(inlineOf("run `pnpm test` **first** and *then*").map((part) => part.kind)).toEqual(["text", "code", "text", "strong", "text", "em"]);
  });

  it("only makes a link of a safe address, and leaves anything else as words", () => {
    expect(inlineOf("[docs](https://memnox.com)")[0]).toEqual({ kind: "link", text: "docs", href: "https://memnox.com" });
    expect(inlineOf("[x](javascript:alert)")[0]).toEqual({ kind: "text", text: "x" });
  });
});
