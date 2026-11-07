import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Memory as the runtime's daemon/memory.ts writes it.
final class MemoryProtocolTests: XCTestCase {
    static let source = #"{"id":"src_1","kind":"obsidian","name":"Vault","location":"/Users/sam/vault","trust":"trusted","scope":"personal","watched":true,"keyHeld":true,"lastReadAt":"2026-10-30T10:00:00Z","counts":{"candidate":2,"verified":3,"conflicting":0,"outdated":1,"rejected":0}}"#

    static let item = #"{"id":"mem_1","kind":"rule","statement":"  Never push to main.  ","subject":"git","status":"candidate","scope":"project","project":"app","origin":"agent","tainted":true,"extractorConfidence":0.82,"suggestedBy":"claude-code","rule":{"effect":"deny","actions":["git.push"],"targets":["main"],"reason":"Main is protected","sentence":"Deny git.push to main"},"duplicateOf":{"id":"mem_0","statement":"Main is protected."},"proposalId":"prp_1","evidence":[{"ref":"notes/git.md#Main","document":"notes/git.md","heading":"Main","source":"Vault","stale":true},{"ref":"https://x.test/p","document":"p","url":"https://x.test/p","source":"Vault","stale":false}],"createdAt":"2026-10-29T10:00:00Z","decidedAt":"2026-10-30T10:00:00Z","decidedBy":"Sam"}"#

    func testReadsSourcesQueueFactsAndAnItem() throws {
        let response = try line(#"{"id":1,"ok":true,"memorySources":["# + Self.source + #"],"memoryLearn":{"items":["# + Self.item + #"],"more":3},"memoryFacts":{"items":[],"more":0},"memoryItem":"# + Self.item + "}")
        let source = try XCTUnwrap(response.memorySources?.first)
        XCTAssertEqual(source.sourceKind, .obsidian)
        XCTAssertEqual(source.sourceTrust, .trusted)
        XCTAssertEqual(source.counts, MemorySourceCounts(candidate: 2, verified: 3, outdated: 1))
        XCTAssertEqual(source.keyHeld, true)
        XCTAssertNil(source.lastError)
        let item = try XCTUnwrap(response.memoryLearn?.items.first)
        XCTAssertEqual(response.memoryLearn?.more, 3)
        XCTAssertEqual(item.statement, "  Never push to main.  ")
        XCTAssertEqual(item.memoryKind, .rule)
        XCTAssertEqual(item.memoryStatus, .candidate)
        XCTAssertEqual(item.memoryScope, .project)
        XCTAssertEqual(item.memoryOrigin, .agent)
        XCTAssertEqual(item.rule?.sentence, "Deny git.push to main")
        XCTAssertNil(item.rule?.agents)
        XCTAssertEqual(item.duplicateOf, MemoryDuplicateView(id: "mem_0", statement: "Main is protected."))
        XCTAssertEqual(item.evidence.map(\.stale), [true, false])
        XCTAssertEqual(item.evidence.last?.url, "https://x.test/p")
        XCTAssertNil(item.evidence.last?.heading)
        XCTAssertEqual(response.memoryFacts?.items, [])
        XCTAssertEqual(response.memoryItem?.proposalId, "prp_1")
    }

    func testReadsAReadSummary() throws {
        let response = try line(#"{"id":2,"ok":true,"memoryRead":{"sourceId":"src_1","documents":4,"passages":12,"added":3,"merged":2,"rejectedBefore":0,"droppedCitations":1,"discarded":0,"outdated":0,"extractor":"unavailable"}}"#)
        let read = try XCTUnwrap(response.memoryRead)
        XCTAssertEqual(read.extractorState, .unavailable)
        XCTAssertEqual(read.droppedCitations, 1)
        XCTAssertNil(read.error)
        XCTAssertNil(read.skipped)
    }

    func testReadsWhatAReadPassedOverAndKeepsAReasonItDoesNotKnow() throws {
        let response = try line(#"{"id":2,"ok":true,"memoryRead":{"sourceId":"src_1","documents":1,"passages":2,"added":0,"merged":0,"rejectedBefore":0,"droppedCitations":0,"discarded":0,"outdated":0,"extractor":"answered","skipped":[{"document":"dump.md","reason":"too-large"},{"document":"x.md","reason":"encrypted"}]}}"#)
        let skipped = try XCTUnwrap(response.memoryRead?.skipped)
        XCTAssertEqual(skipped.map(\.skipReason), [.tooLarge, nil])
        XCTAssertEqual(skipped.last?.reason, "encrypted")
    }

    func testAnOlderRuntimeLeavesMemoryOutAndANewerValueIsKeptButNotNamed() throws {
        let older = try line(#"{"id":3,"ok":true}"#)
        XCTAssertNil(older.memorySources)
        XCTAssertNil(older.memoryRead)
        XCTAssertNil(older.memoryLearn)
        XCTAssertNil(older.memoryFacts)
        XCTAssertNil(older.memoryItem)
        let newer = try JSONDecoder().decode(MemoryItemView.self, from: Data(#"{"id":"m","kind":"habit","statement":"s","subject":"x","status":"archived","scope":"team","origin":"import","tainted":false,"evidence":[],"createdAt":"2026-10-30T00:00:00Z"}"#.utf8))
        XCTAssertNil(newer.memoryKind)
        XCTAssertNil(newer.memoryStatus)
        XCTAssertEqual(newer.status, "archived")
    }

    func testWritesEachRequestWithOnlyTheFieldsItCarries() throws {
        var add = DaemonRequest(id: 4, method: .memorySourceAdd)
        add.memorySource = MemorySourceInput(kind: .supermemory, scope: .personal, secret: "SUPERMEMORY_API_KEY")
        let added = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(add)) as? [String: Any])
        XCTAssertEqual(added["method"] as? String, "memory-source-add")
        XCTAssertEqual(added["memorySource"] as? [String: String], ["kind": "supermemory", "scope": "personal", "secret": "SUPERMEMORY_API_KEY"])

        var edit = DaemonRequest(id: 5, method: .memoryEdit)
        edit.memoryItemId = "mem_1"
        edit.memoryEdit = MemoryEditInput(statement: " Ship on Tuesdays ")
        let edited = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(edit)) as? [String: Any])
        XCTAssertEqual(edited["memoryItemId"] as? String, "mem_1")
        XCTAssertEqual(edited["memoryEdit"] as? [String: String], ["statement": " Ship on Tuesdays "])

        var facts = DaemonRequest(id: 6, method: .memoryFacts)
        facts.memoryStatus = MemoryStatus.outdated.rawValue
        facts.memoryScope = MemoryScope.project.rawValue
        let listed = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(facts)) as? [String: Any])
        XCTAssertEqual(listed["memoryStatus"] as? String, "outdated")
        XCTAssertEqual(listed["memoryScope"] as? String, "project")
        XCTAssertNil(listed["memoryQuery"])
    }

    func testNamesEveryMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.memorySources, .memorySourceAdd, .memorySourceRemove, .memorySourceRead, .memoryLearn,
                                       .memoryConfirm, .memoryReject, .memoryEdit, .memorySearch, .memoryFacts, .memoryForget,
                                       .workspaceMemory, .workspaceGraph]
        XCTAssertEqual(methods.map(\.rawValue), ["memory-sources", "memory-source-add", "memory-source-remove", "memory-source-read",
                                                 "memory-learn", "memory-confirm", "memory-reject", "memory-edit", "memory-search",
                                                 "memory-facts", "memory-forget", "workspace-memory",
                                                 "workspace-graph"])
    }
}
