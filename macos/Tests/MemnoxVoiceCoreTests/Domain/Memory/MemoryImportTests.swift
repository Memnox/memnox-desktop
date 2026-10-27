import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The Add source sheet's path: what each kind lets the person pick, how a typed or dropped path is read, what the look
/// on disk says before adding, and how a first read is said after.
final class MemoryImportTests: XCTestCase {
    func testAMarkdownSourceTakesFilesAndAVaultOnlyAFolder() {
        XCTAssertTrue(MemoryImport.pick(.markdown).files)
        XCTAssertEqual(MemoryImport.pick(.markdown).panelExtensions, ["md", "markdown", "mdc"])
        XCTAssertFalse(MemoryImport.pick(.obsidian).files)
        XCTAssertTrue(MemoryImport.pick(.obsidian).folders)
        XCTAssertEqual(MemoryImport.pick(.instructions).panelExtensions, ["mdc", "md", "cursorrules"])
        XCTAssertEqual(MemoryImport.pick(.notionExport).panelExtensions, ["md", "markdown", "mdc", "zip"])
        XCTAssertTrue(MemoryImport.reads(file: "/notes/devGuidelines.md", kind: .markdown))
        XCTAssertTrue(MemoryImport.reads(file: "/repo/README.MARKDOWN", kind: .markdown))
        XCTAssertFalse(MemoryImport.reads(file: "/repo/notes.txt", kind: .markdown))
        XCTAssertTrue(MemoryImport.reads(file: "/repo/CLAUDE.md", kind: .instructions))
        XCTAssertFalse(MemoryImport.reads(file: "/repo/README.md", kind: .instructions))
    }

    func testReadsPathsTypedPastedOrDroppedOneALine() {
        let text = "  \"/Users/sam/notes/README.md\"  \nfile:///Users/sam/My%20Notes/\n~/vault/\n\n/Users/sam/notes/README.md"
        XCTAssertEqual(MemoryImport.paths(text, home: "/Users/sam"),
                       ["/Users/sam/notes/README.md", "/Users/sam/My Notes", "/Users/sam/vault"])
        XCTAssertEqual(MemoryImport.paths("   ", home: "/Users/sam"), [])
        XCTAssertEqual(MemoryImport.field(["/a", "/b"]), "/a\n/b")
    }

    func testCountsTheNotesTheWalkReads() {
        XCTAssertTrue(MemoryImport.counts(relativePath: "team/people.md", kind: .obsidian))
        XCTAssertFalse(MemoryImport.counts(relativePath: ".obsidian/workspace.md", kind: .obsidian))
        XCTAssertFalse(MemoryImport.counts(relativePath: "web/node_modules/pkg/README.md", kind: .markdown))
        XCTAssertFalse(MemoryImport.counts(relativePath: "image.png", kind: .markdown))
        XCTAssertTrue(MemoryImport.counts(relativePath: "CLAUDE.md", kind: .instructions))
        XCTAssertTrue(MemoryImport.counts(relativePath: ".cursor/rules/style.mdc", kind: .instructions))
        XCTAssertFalse(MemoryImport.counts(relativePath: "docs/CLAUDE.md", kind: .instructions))
    }

    func testSaysWhyAPathWillNotDo() {
        XCTAssertEqual(MemoryImport.check([], kind: .markdown), .nothing)
        XCTAssertEqual(MemoryImport.check([PathLook(path: "notes", kind: .folder)], kind: .markdown),
                       .problem("Give the whole path, from the top of the drive."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/gone", kind: .missing)], kind: .markdown), .problem("/gone is not on this Mac."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/n/a.md", kind: .file, readable: false)], kind: .markdown),
                       .problem("Memnox cannot open a.md. Pick it with Choose, so macOS lets Memnox read it."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/n/a.md", kind: .file)], kind: .obsidian),
                       .problem("An Obsidian vault is a folder: choose the vault rather than one note."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/n/a.txt", kind: .file)], kind: .markdown),
                       .problem("a.txt is not Markdown. Choose a .md or .markdown file, or a folder."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/code/app", kind: .folder)], kind: .instructions),
                       .problem("No CLAUDE.md, AGENTS.md, GEMINI.md or Cursor rules in app."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/n/empty", kind: .folder)], kind: .markdown),
                       .problem("No Markdown files in empty."))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/n/x.zip", kind: .file)], kind: .markdown),
                       .problem("x.zip is not Markdown. Choose a .md or .markdown file, or a folder."))
    }

    func testShowsWhatWillBeReadBeforeAdding() {
        let found = (1...7).map { "note\($0).md" }
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/Users/sam/labvanced", kind: .folder, found: found)], kind: .markdown),
                       .ready(ImportPreview(headline: "7 Markdown files in labvanced", names: Array(found.prefix(5)), more: 2, note: nil)))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/v", kind: .folder, found: ["a.md"], cut: true)], kind: .obsidian),
                       .ready(ImportPreview(headline: "At least 1 Markdown file in v", names: ["a.md"], more: 0, note: nil)))
        XCTAssertEqual(MemoryImport.check([PathLook(path: "/l/devGuidelines.md", kind: .file), PathLook(path: "/l/README.md", kind: .file)], kind: .markdown),
                       .ready(ImportPreview(headline: "2 Markdown files chosen", names: ["devGuidelines.md", "README.md"], more: 0,
                                            note: "Each is added as its own source, and read now.")))
        guard case .ready(let zip) = MemoryImport.check([PathLook(path: "/d/Export.zip", kind: .file)], kind: .notionExport) else {
            return XCTFail("a Notion zip is ready")
        }
        XCTAssertEqual(zip.headline, "A Notion export zip, Export.zip")
    }

    func testAddsOneSourcePerPathAndKeepsANameOnlyForOne() {
        let one = MemoryImport.inputs(SourceForm(kind: .markdown, location: "~/notes/README.md", name: "Readme"), home: "/Users/sam")
        XCTAssertEqual(one, [MemorySourceInput(kind: .markdown, location: "/Users/sam/notes/README.md", name: "Readme", scope: .personal)])
        let two = MemoryImport.inputs(SourceForm(kind: .markdown, location: "/l/a.md\n/l/b.md", name: "Ignored"), home: "/Users/sam")
        XCTAssertEqual(two.map(\.location), ["/l/a.md", "/l/b.md"])
        XCTAssertEqual(two.map(\.name), [nil, nil])
        XCTAssertEqual(MemoryImport.inputs(SourceForm(kind: .supermemory), home: "/Users/sam"),
                       [MemorySourceInput(kind: .supermemory, scope: .personal, secret: "SUPERMEMORY_API_KEY")])
    }

    func testFindsTheSourceAnAddMade() {
        let old = MemorySourceView(id: "src_1", kind: .obsidian, name: "Vault", location: "/v")
        let new = MemorySourceView(id: "src_2", kind: .markdown, name: "README.md", location: "/l/README.md")
        XCTAssertEqual(MemoryImport.added(before: ["src_1"], after: [old, new]), [new])
    }

    func testSaysWhatAReadPassedOverAndWhy() {
        XCTAssertNil(MemoryImport.skippedLine(nil))
        XCTAssertNil(MemoryImport.skippedLine([]))
        let skipped = [
            MemorySkippedDocument(document: "dump.md", reason: .tooLarge),
            MemorySkippedDocument(document: "gone.md", reason: .unreadable),
            MemorySkippedDocument(document: "n501.md", reason: .pastLimit),
        ]
        XCTAssertEqual(MemoryImport.skippedLine(skipped),
                       "Passed over 1 file too large to be notes (dump.md) and 1 file that could not be opened (gone.md). Stopped at the most notes one source reads, so the rest were not read.")
    }

    func testSaysEachFirstRead() {
        XCTAssertEqual(MemoryImport.resultLine(ImportResult(name: "a.md", failure: "a.md is not here.")), "a.md was not added: a.md is not here.")
        XCTAssertEqual(MemoryImport.resultLine(ImportResult(name: "a.md")), "a.md was added. Memnox is reading it now.")
        let summary = MemoryReadSummary(sourceId: "s", documents: 1, passages: 2, added: 1, extractor: .answered)
        XCTAssertEqual(MemoryImport.resultLine(ImportResult(name: "a.md", summary: summary)), MemoryLines.readSummaryLine(summary))
        XCTAssertEqual(MemoryImport.readingLine("labvanced", step: 2, of: 3),
                       "Your agent is reading labvanced (2 of 3). This can take a minute, and closing this keeps it reading.")
    }
}
