import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/memory.test.ts, with Touch ID and this Mac where Windows names its own.
final class MemoryLinesTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!

    static func item(_ id: String, kind: MemoryKind = .fact, status: MemoryStatus = .candidate, origin: MemoryOrigin = .extracted,
                     createdAt: String = "2026-10-29T10:00:00Z") -> MemoryItemView {
        MemoryItemView(id: id, kind: kind, statement: "  Releases ship on Tuesdays, never Fridays.  ", subject: "releases", status: status,
                       origin: origin,
                       evidence: [MemoryEvidenceView(ref: "notes/ops.md#Releases", document: "notes/ops.md", heading: "Releases", source: "Vault")],
                       createdAt: createdAt)
    }

    static let source = MemorySourceView(id: "src_1", kind: .obsidian, name: "Vault", location: "/Users/sam/vault/", watched: true,
                                         counts: MemorySourceCounts(candidate: 2, verified: 3, outdated: 1))

    static let summary = MemoryReadSummary(sourceId: "src_1", documents: 4, passages: 12, added: 3, merged: 2, droppedCitations: 1,
                                           extractor: .answered)

    func testSaysEachStatusAndTrustInWordsBesideATone() {
        XCTAssertEqual(MemoryLines.statusWord("verified").word, "Verified")
        XCTAssertEqual(MemoryLines.statusWord("verified").tone, .good)
        XCTAssertEqual(MemoryLines.statusWord("conflicting").tone, .bad)
        XCTAssertEqual(MemoryLines.statusWord("archived").word, "archived")
        XCTAssertEqual(MemoryLines.trustWord("trusted").word, "Trusted: your own files")
        XCTAssertEqual(MemoryLines.trustWord("tainted").word, "Untrusted: written outside your own files")
    }

    func testCountsWhatASourceTaughtLeavingZerosOutNeverAScore() {
        XCTAssertEqual(MemoryLines.sourceCountsLine(Self.source.counts), "3 verified, 2 to confirm, 1 outdated")
        XCTAssertEqual(MemoryLines.sourceCountsLine(MemorySourceCounts()), "Taught nothing yet")
    }

    func testSaysWhenASourceWasReadAndWhetherItIsWatchedAndAKeyOnlyByWhetherItIsHeld() {
        let read = MemorySourceView(id: "s", kind: .obsidian, name: "Vault", location: "/v", watched: true, lastReadAt: "2026-10-30T10:00:00Z")
        XCTAssertEqual(MemoryLines.lastReadLine(read, now: now), "Read 2 h ago. Read again when a file in it changes.")
        let unread = MemorySourceView(id: "s", kind: .supermemory, name: "Supermemory", location: "https://api.supermemory.ai")
        XCTAssertEqual(MemoryLines.lastReadLine(unread, now: now), "Not read yet. Read when you ask.")
        XCTAssertEqual(MemoryLines.keyLine(false), "Its key is not set on this Mac, so it cannot be read.")
        XCTAssertEqual(MemoryLines.keyLine(true), "Its key is kept by this Mac.")
        XCTAssertNil(MemoryLines.keyLine(nil))
    }

    func testSaysAReadSoAnEmptyOneAndAFailedOneAreToldApart() {
        XCTAssertEqual(MemoryLines.readSummaryLine(Self.summary),
                       "Read 4 documents and 12 passages: 3 added, 2 merged into what was known, 1 citation dropped for naming no passage. Your agent read the new passages.")
        XCTAssertEqual(MemoryLines.readSummaryLine(MemoryReadSummary(sourceId: "s", error: "the folder is gone")), "The read failed: the folder is gone")
        XCTAssertEqual(MemoryLines.extractorLine("unavailable"),
                       "No agent on this Mac could read the new passages, so they wait for the next read. Sign in to Claude Code and read again.")
        XCTAssertEqual(MemoryLines.extractorLine("idle"), "Nothing new to read.")
    }

    func testLabelsAConfidenceAsTheExtractorsOwnAndNamesWhoSuggestedAnItem() {
        XCTAssertEqual(MemoryLines.confidenceLine(0.823), "The extractor\u{2019}s own confidence: 82%")
        XCTAssertEqual(MemoryLines.confidenceLine(1.4), "The extractor\u{2019}s own confidence: 100%")
        XCTAssertNil(MemoryLines.confidenceLine(nil))
        XCTAssertEqual(MemoryLines.originLine(origin: "agent", suggestedBy: "claude-code"), "Suggested by Claude Code through memnox_suggest")
        XCTAssertEqual(MemoryLines.originLine(origin: "agent", suggestedBy: nil), "Suggested by an agent through memnox_suggest")
        XCTAssertEqual(MemoryLines.originLine(origin: "extracted", suggestedBy: nil), "Read out of a source by your agent")
        XCTAssertEqual(MemoryLines.originLine(origin: "person", suggestedBy: nil), "Written by a person")
    }

    func testQuotesADuplicateAndMarksStaleEvidence() {
        XCTAssertEqual(MemoryLines.duplicateLine("Ship on Tuesdays."), "Restates \u{201C}Ship on Tuesdays.\u{201D}")
        let stale = MemoryEvidenceView(ref: "notes/ops.md#Releases", document: "notes/ops.md", source: "Vault", stale: true)
        XCTAssertEqual(MemoryLines.evidenceLine(stale), "notes/ops.md#Releases in Vault, changed since it was read")
        let decided = MemoryItemView(id: "v", statement: "s", status: .verified, createdAt: "2026-10-27T00:00:00Z", decidedAt: "2026-10-28T12:00:00Z",
                                     decidedBy: "Sam")
        XCTAssertEqual(MemoryLines.decidedLine(decided, now: now), "Confirmed by Sam 2 d ago")
        XCTAssertNil(MemoryLines.decidedLine(Self.item("c"), now: now))
    }

    func testFindsTheWholePathOfAPieceOfEvidenceFromItsSource() {
        let evidence = MemoryEvidenceView(ref: "notes/ops.md#Releases", document: "notes/ops.md", source: "Vault")
        XCTAssertEqual(MemoryLines.evidencePath(evidence, sources: [Self.source]), "/Users/sam/vault/notes/ops.md")
        XCTAssertEqual(MemoryLines.evidencePath(evidence, sources: nil), "notes/ops.md")
    }

    func testSaysWhereAnItemIsKeptAndCaptionsItsRow() {
        XCTAssertEqual(MemoryLines.keptLine(Self.item("a")), "In your personal memory")
        XCTAssertEqual(MemoryLines.keptLine(MemoryItemView(id: "p", statement: "s", scope: .project, project: "app", createdAt: "x")),
                       "With the project app")
        XCTAssertEqual(MemoryLines.rowCaption(Self.item("a")), "Fact \u{00B7} Personal \u{00B7} 1 piece of evidence")
    }

    func testOrdersTheQueueOldestFirstAndCountsItForHome() {
        let queue = MemoryLines.oldestFirst([Self.item("b", createdAt: "2026-10-30T00:00:00Z"), Self.item("a")])
        XCTAssertEqual(queue.map(\.id), ["a", "b"])
        XCTAssertEqual(MemoryLines.learnWaitingLine(1), "1 thing to confirm in Learn")
        XCTAssertEqual(MemoryLines.learnWaitingLine(4), "4 things to confirm in Learn")
        XCTAssertNil(MemoryLines.moreLine(0))
        XCTAssertEqual(MemoryLines.moreLine(7), "7 more not shown")
    }

    func testSaysAConfirmedRuleWaitsOnTheIsland() {
        XCTAssertEqual(MemoryLines.confirmedLine(kind: "rule", proposed: true, keyTitle: "Touch ID"),
                       "The rule waits for your signature on the island. Confirm it with Touch ID and it holds.")
        XCTAssertEqual(MemoryLines.confirmedLine(kind: "fact", proposed: false, keyTitle: "Touch ID"),
                       "Confirmed. The fact is verified now, and your agents are handed it.")
    }

    func testChecksTheAddSourceFormAndSendsAKeyByItsNameOnly() {
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .obsidian)), "Choose the folder it reads.")
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .instructions)), "Choose the repository whose instruction files it reads.")
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .markdown, location: "notes")), "Give the whole path, from the top of the drive.")
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .mcp, server: "memory")), "Choose the tool that reads its memory.")
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .mcp)), "Choose the hub server it reads.")
        XCTAssertNil(MemoryLines.sourceFormProblem(SourceForm(kind: .supermemory)))
        XCTAssertEqual(MemoryLines.sourceFormProblem(SourceForm(kind: .supermemory, secret: " ")), "Name the secret that holds the key.")
        XCTAssertEqual(MemoryLines.sourceInput(SourceForm(kind: .supermemory, location: "/ignored")),
                       MemorySourceInput(kind: .supermemory, scope: .personal, secret: "SUPERMEMORY_API_KEY"))
        XCTAssertEqual(MemoryLines.sourceInput(SourceForm(kind: .instructions, location: " /code/app ", name: "App", scope: .project)),
                       MemorySourceInput(kind: .instructions, location: "/code/app", name: "App", scope: .project))
        XCTAssertEqual(MemoryLines.sourceInput(SourceForm(kind: .mcp, server: "memory", tool: "search")),
                       MemorySourceInput(kind: .mcp, scope: .personal, server: "memory", tool: "search"))
    }
}
