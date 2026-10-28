import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/memory.test.ts.
final class MemoryTests: XCTestCase {
    private static let source = MemoryProtocolTests.source
    private static func item(_ id: String, kind: String = "fact", status: String = "candidate") -> String {
        #"{"id":""# + id + #"","kind":""# + kind + #"","statement":"  Releases ship on Tuesdays, never Fridays.  ","subject":"releases","status":""# + status
            + #"","scope":"personal","origin":"extracted","tainted":false,"evidence":[],"createdAt":"2026-10-29T10:00:00Z"}"#
    }

    func testReadsSourcesAndTheQueueAndSaysWhenTheRuntimeDoesNotAnswer() async throws {
        let link = ScriptedLink()
        link.answers["memory-sources"] = [try line(#"{"id":1,"ok":true,"memorySources":["# + Self.source + "]}")]
        link.answers["memory-learn"] = [try line(#"{"id":2,"ok":true,"memoryLearn":{"items":["# + Self.item("a") + #"],"more":0}}"#)]
        let memory = Memory(link: link)
        await memory.refreshSources()
        await memory.refreshLearn()
        XCTAssertEqual(memory.sources?.first?.id, "src_1")
        XCTAssertEqual(memory.learn?.items.first?.statement, "  Releases ship on Tuesdays, never Fridays.  ")
        XCTAssertEqual(memory.unreadable, MemoryUnreadable())

        let down = ScriptedLink()
        down.unreachable = true
        let gone = Memory(link: down)
        await gone.refreshLearn()
        XCTAssertTrue(gone.unreadable.learn)
        XCTAssertFalse(gone.unreadable.sources)
    }

    func testReadsTheWorkspacePullAndWhetherThisMacIsJoinedOffTheRuntime() async throws {
        let link = ScriptedLink()
        link.answers["workspace-memory"] = [try line(#"{"id":1,"ok":true,"workspaceMemory":{"hash":"h","facts":[{"id":"f1","kind":"decision","statement":"Retry three times.","subject":"payments","verifiedBy":"Ben"}],"unconfirmed":[{"id":"c1","kind":"decision","statement":"Ship Monday.","subject":"beta","standing":"candidate","approved":false,"sources":["slack"],"saidBy":["Cara"],"untrusted":true}],"withheld":1,"syncedAt":"2026-10-30T12:00:00Z"}}"#)]
        link.answers["machine"] = [try line(#"{"id":2,"ok":true,"machine":{"signedIn":true,"name":"Acme"}}"#)]
        let memory = Memory(link: link)
        await memory.refreshWorkspace()
        XCTAssertEqual(link.sent.map(\.method), ["workspace-memory", "workspace-graph", "machine"])
        XCTAssertEqual(memory.workspace?.facts.first?.verifiedBy, "Ben")
        XCTAssertEqual(memory.workspace?.unconfirmed.first?.saidBy, ["Cara"])
        XCTAssertEqual(memory.workspace?.unconfirmed.first?.untrusted, true)
        XCTAssertEqual(memory.workspace?.withheld, 1)
        XCTAssertEqual(memory.joined, true)
        XCTAssertFalse(memory.unreadable.workspace)

        let never = ScriptedLink()
        never.answers["workspace-memory"] = [try line(#"{"id":1,"ok":true}"#)]
        never.answers["machine"] = [try line(#"{"id":2,"ok":true,"machine":{"signedIn":false}}"#)]
        let fresh = Memory(link: never)
        await fresh.refreshWorkspace()
        XCTAssertNil(fresh.workspace)
        XCTAssertEqual(fresh.joined, false)

        let down = ScriptedLink()
        down.unreachable = true
        let gone = Memory(link: down)
        await gone.refreshWorkspace()
        XCTAssertTrue(gone.unreadable.workspace)
        XCTAssertNil(gone.joined)
    }

    func testReadsTheLiveGraphOffTheRuntimeAndAsksFreshOnlyOnRefresh() async throws {
        let link = ScriptedLink()
        link.answers["workspace-memory"] = [try line(#"{"id":1,"ok":true}"#)]
        let graph = #"{"id":2,"ok":true,"workspaceGraph":{"nodes":[{"id":"item:ev1","kind":"document","label":"Beta on Monday","tool":"slack","count":21,"weight":3},{"id":"x","kind":"martian","label":"?","weight":0},{"kind":"broken"}],"links":[{"from":"source:slack","to":"item:ev1","kind":"carries"}],"withheld":2,"truncated":false,"source":"live","readAt":"2026-11-01T09:00:00Z"}}"#
        link.answers["workspace-graph"] = [try line(graph)]
        link.answers["machine"] = [try line(#"{"id":3,"ok":true,"machine":{"signedIn":true}}"#)]
        let memory = Memory(link: link)

        await memory.refreshWorkspace()
        XCTAssertEqual(memory.workspaceGraph?.graphSource, .live)
        XCTAssertEqual(memory.workspaceGraph?.withheld, 2)
        // An unknown kind is kept as sent and read as nil; a node missing its id is dropped alone.
        XCTAssertEqual(memory.workspaceGraph?.nodes.map(\.id), ["item:ev1", "x"])
        XCTAssertNil(memory.workspaceGraph?.nodes.last?.nodeKind)
        XCTAssertEqual(memory.workspaceGraph?.nodes.first?.count, 21)
        XCTAssertNil(link.sent[1].workspaceGraphFresh)

        link.answers["workspace-graph"] = [try line(#"{"id":5,"ok":false,"error":"no"}"#)]
        await memory.refreshWorkspace(fresh: true)
        XCTAssertEqual(link.sent[4].workspaceGraphFresh, true)
        // A refused read keeps the last picture rather than blanking it.
        XCTAssertEqual(memory.workspaceGraph?.nodes.first?.id, "item:ev1")
    }

    func testListsByStatusAndScopeAndSearchesWhenWordsAreTyped() async throws {
        let link = ScriptedLink()
        link.answers["memory-facts"] = [try line(#"{"id":1,"ok":true,"memoryFacts":{"items":["# + Self.item("v", status: "verified") + #"],"more":2}}"#)]
        link.answers["memory-search"] = [try line(#"{"id":2,"ok":true,"memoryFacts":{"items":[],"more":0}}"#)]
        let memory = Memory(link: link)
        await memory.show(MemoryFilter(status: .outdated, scope: .project))
        XCTAssertEqual(link.sent.first?.method, "memory-facts")
        XCTAssertEqual(link.sent.first?.memoryStatus, "outdated")
        XCTAssertEqual(link.sent.first?.memoryScope, "project")
        XCTAssertEqual(memory.facts?.more, 2)
        await memory.show(MemoryFilter(status: .verified, query: " tuesday "))
        XCTAssertEqual(link.sent.last?.method, "memory-search")
        XCTAssertEqual(link.sent.last?.memoryQuery, "tuesday")
        XCTAssertNil(link.sent.last?.memoryStatus)
        XCTAssertEqual(memory.facts?.items, [])
        XCTAssertEqual(memory.filter, MemoryFilter(status: .verified, query: " tuesday "))
    }

    func testKeepsHowASearchWasAnsweredAndReadsAnOlderRuntimeAsKeyword() async throws {
        let link = ScriptedLink()
        link.answers["memory-search"] = [try line(#"{"id":1,"ok":true,"memoryFacts":{"items":[],"more":0},"memorySearchMode":"semantic"}"#)]
        link.answers["memory-facts"] = [try line(#"{"id":4,"ok":true,"memoryFacts":{"items":[],"more":0}}"#)]
        let memory = Memory(link: link)
        await memory.show(MemoryFilter(status: .verified, query: "release days"))
        XCTAssertEqual(memory.search, MemorySearch(mode: .semantic))
        link.answers["memory-search"] = [try line(#"{"id":2,"ok":true,"memoryFacts":{"items":[],"more":0},"memorySearchMode":"keyword","memorySearchNote":"The embedding model did not answer."}"#)]
        await memory.show(MemoryFilter(status: .verified, query: "release"))
        XCTAssertEqual(memory.search, MemorySearch(mode: .keyword, note: "The embedding model did not answer."))
        link.answers["memory-search"] = [try line(#"{"id":3,"ok":true,"memoryFacts":{"items":[],"more":0}}"#)]
        await memory.show(MemoryFilter(status: .verified, query: "older"))
        XCTAssertEqual(memory.search, MemorySearch(mode: .keyword))
        await memory.show(MemoryFilter(status: .verified))
        XCTAssertNil(memory.search)
        XCTAssertEqual(MemoryLines.searchModeLine(.keyword), "Searched by keyword")
        XCTAssertEqual(MemoryLines.searchModeLine(.semantic), "Searched by meaning, and by keyword")
    }

    func testReadsASourceNowAndKeepsTheSummaryUnderItsCard() async throws {
        let link = ScriptedLink()
        link.answers["memory-source-read"] = [try line(#"{"id":1,"ok":true,"memorySources":["# + Self.source + #"],"memoryRead":{"sourceId":"src_1","documents":4,"passages":12,"added":3,"merged":2,"rejectedBefore":0,"droppedCitations":1,"discarded":0,"outdated":0,"extractor":"unavailable"}}"#)]
        let memory = Memory(link: link)
        let outcome = await memory.readNow("src_1")
        guard case .done = outcome else { return XCTFail("expected a read, got \(outcome)") }
        XCTAssertEqual(memory.lastRead("src_1")?.extractorState, .unavailable)
        XCTAssertEqual(link.sent.first?.memorySourceId, "src_1")
        XCTAssertEqual(memory.sources?.count, 1)
        XCTAssertNil(memory.busy)
    }

    func testConfirmsARuleAsAProposalOnTheIslandAndPassesARefusalOnInTheRuntimesWords() async throws {
        let link = ScriptedLink()
        link.answers["memory-confirm"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_1","memoryItem":"# + Self.item("r", kind: "rule") + #","memoryLearn":{"items":[],"more":0}}"#)]
        link.answers["memory-reject"] = [try line(#"{"id":2,"ok":false,"error":"No memory x."}"#)]
        let memory = Memory(link: link)
        let confirmed = await memory.confirm("r", keyTitle: "Touch ID")
        XCTAssertEqual(confirmed, .proposed(id: "prp_1", note: "The rule waits for your signature on the island. Confirm it with Touch ID and it holds."))
        XCTAssertEqual(memory.learn?.items, [])
        let refused = await memory.reject("x")
        XCTAssertEqual(refused, .failed("No memory x."))
        XCTAssertEqual(refused.note, "No memory x.")
    }

    func testAddsASourceAndSaysItIsBeingRead() async throws {
        let link = ScriptedLink()
        link.answers["memory-source-add"] = [try line(#"{"id":1,"ok":true,"memorySources":["# + Self.source + "]}")]
        let memory = Memory(link: link)
        let outcome = await memory.addSource(MemorySourceInput(kind: .obsidian, location: "/Users/sam/vault", scope: .personal))
        XCTAssertEqual(outcome, .done("Added. Memnox is reading it now, and what it finds waits in Learn."))
        XCTAssertEqual(link.sent.first?.memorySource?.location, "/Users/sam/vault")
        XCTAssertEqual(memory.sources?.count, 1)
    }

    func testSendsAnEditVerbatimAndForgetsAnItemOutOfTheList() async throws {
        let link = ScriptedLink()
        link.answers["memory-edit"] = [try line(#"{"id":1,"ok":true}"#)]
        link.answers["memory-facts"] = [try line(#"{"id":2,"ok":true,"memoryFacts":{"items":["# + Self.item("v") + "," + Self.item("w") + #"],"more":0}}"#)]
        link.answers["memory-forget"] = [try line(#"{"id":3,"ok":true}"#)]
        let memory = Memory(link: link)
        let saved = await memory.edit("a", statement: " Ship on Tuesdays ")
        XCTAssertEqual(saved, .done("Saved. Confirm it when it says what you mean."))
        XCTAssertEqual(link.sent.first?.memoryItemId, "a")
        XCTAssertEqual(link.sent.first?.memoryEdit, MemoryEditInput(statement: " Ship on Tuesdays "))
        await memory.show(MemoryFilter())
        let forgotten = await memory.forget("v")
        XCTAssertEqual(forgotten, .done("Forgotten, with its evidence."))
        XCTAssertEqual(memory.facts?.items.map(\.id), ["w"])
    }
}
