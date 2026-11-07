import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/personal-sync.test.ts.
final class PersonalSyncTests: XCTestCase {
    private static let ready = #"{"state":"ready","said":"Synced.","kinds":[{"kind":"servers","items":3}],"conflicts":1,"skipped":[],"openedElsewhere":[],"waiting":[{"machineId":"laptop","fingerprint":"12345 67890 11121 31415 16171 81920","sealed":false}]}"#
    private static let settled = #"{"state":"ready","said":"Synced.","kinds":[],"conflicts":0,"skipped":[],"openedElsewhere":[],"waiting":[]}"#
    private static let conflict = #"{"id":"c_1","kind":"skills","name":"release-notes","writtenBy":"laptop","keptAt":"2026-10-30T10:00:00Z","theirs":"v2","mine":"v3"}"#

    func testReadsTheStatusSyncsNowAndOpensTheConflictsBesideThisMacsOwn() async throws {
        let link = ScriptedLink()
        link.answers["personal-sync-status"] = [try line(#"{"id":1,"ok":true,"personalSync":"# + Self.ready + "}")]
        link.answers["personal-sync-now"] = [try line(#"{"id":1,"ok":true,"personalSync":"# + Self.settled + "}")]
        link.answers["personal-sync-conflicts"] = [try line(#"{"id":1,"ok":true,"personalSync":"# + Self.ready + #","syncConflicts":["# + Self.conflict + "]}")]
        link.answers["personal-sync-resolve"] = [try line(#"{"id":1,"ok":true,"personalSync":"# + Self.settled + "}")]
        let sync = PersonalSync(link: link)
        await sync.refresh()
        XCTAssertEqual(sync.status?.waiting.first?.machineId, "laptop")
        let now = await sync.syncNow()
        XCTAssertEqual(now, .done)
        XCTAssertEqual(sync.status?.conflicts, 0)
        _ = await sync.loadConflicts()
        XCTAssertEqual(sync.conflicts?.map(\.id), ["c_1"])
        let kept = await sync.resolve("c_1", keep: .theirs)
        XCTAssertEqual(kept, .done)
        XCTAssertEqual(link.sent.last?.syncConflictId, "c_1")
        XCTAssertEqual(link.sent.last?.syncKeep, "theirs")
        XCTAssertEqual(sync.conflicts, [])
    }

    func testOnlyProposesMovingTheKeySendingTheFingerprintThePersonCompared() async throws {
        let link = ScriptedLink()
        link.answers["personal-sync-key-offer"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_offer","personalSync":"# + Self.ready + "}")]
        link.answers["personal-sync-key-accept"] = [try line(#"{"id":1,"ok":false,"error":"That is not the fingerprint this machine shows."}"#)]
        let sync = PersonalSync(link: link)
        let offered = await sync.offer(machineId: "laptop", fingerprint: "12345 67890 11121 31415 16171 81920")
        XCTAssertEqual(offered, .proposed(id: "prp_offer"))
        XCTAssertEqual(link.sent.last?.syncMachineId, "laptop")
        XCTAssertEqual(link.sent.last?.syncFingerprint, "12345 67890 11121 31415 16171 81920")
        let accepted = await sync.accept(fingerprint: "00000 00000 00000 00000 00000 00000")
        XCTAssertEqual(accepted, .failed("That is not the fingerprint this machine shows."))

        let down = ScriptedLink()
        down.unreachable = true
        let gone = PersonalSync(link: down)
        await gone.refresh()
        XCTAssertTrue(gone.unreadable)
    }
}
