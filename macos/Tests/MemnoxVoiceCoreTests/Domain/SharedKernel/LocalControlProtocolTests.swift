import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The local network, personal sync and shared projects as the runtime's daemon/lan.ts, daemon/personal-sync.ts and
/// daemon/projects.ts write them.
final class LocalControlProtocolTests: XCTestCase {
    func testReadsTheLocalNetwork() throws {
        let response = try line(#"{"id":1,"ok":true,"proposed":"prp_lan","lan":{"on":true,"listening":true,"addresses":["192.168.1.20"],"port":47820,"advertised":true,"instance":"mx-7f3a","reachable":[{"deviceId":"dev_1","name":"Sam's iPhone"}]}}"#)
        let lan = try XCTUnwrap(response.lan)
        XCTAssertEqual(lan, LanStatus(on: true, listening: true, addresses: ["192.168.1.20"], port: 47820, advertised: true,
                                      instance: "mx-7f3a", reachable: [LanPhone(deviceId: "dev_1", name: "Sam's iPhone")]))
        XCTAssertEqual(response.proposed, "prp_lan")
        let off = try line(#"{"id":2,"ok":true,"lan":{"on":false,"listening":false,"addresses":[],"advertised":false,"reachable":[]}}"#)
        XCTAssertNil(off.lan?.port)
        XCTAssertNil(off.lan?.instance)
    }

    func testReadsPersonalSyncAndItsConflicts() throws {
        let response = try line(#"{"id":3,"ok":true,"personalSync":{"state":"ready","said":"Synced.","keyId":"k1","lastSyncedAt":"2026-10-30T11:00:00Z","kinds":[{"kind":"servers","items":3}],"conflicts":1,"skipped":["too large"],"openedElsewhere":["github.com/acme/api"],"waiting":[{"machineId":"laptop","fingerprint":"12345 67890 11121 31415 16171 81920","sealed":false}]},"syncConflicts":[{"id":"c1","kind":"skills","name":"notes","writtenBy":"laptop","keptAt":"2026-10-30T10:00:00Z","theirs":"v2"}]}"#)
        let status = try XCTUnwrap(response.personalSync)
        XCTAssertEqual(status.syncState, .ready)
        XCTAssertEqual(status.kinds, [PersonalSyncKindCount(kind: "servers", items: 3)])
        XCTAssertEqual(status.waiting.first?.fingerprint, "12345 67890 11121 31415 16171 81920")
        XCTAssertNil(status.arrivedFingerprint)
        let conflict = try XCTUnwrap(response.syncConflicts?.first)
        XCTAssertEqual(conflict.theirs, "v2")
        XCTAssertNil(conflict.mine)
        let newer = try line(#"{"id":4,"ok":true,"personalSync":{"state":"paused","said":"s","kinds":[],"conflicts":0,"skipped":[],"openedElsewhere":[],"waiting":[]}}"#)
        XCTAssertNil(newer.personalSync?.syncState)
        XCTAssertEqual(newer.personalSync?.state, "paused")
    }

    func testReadsAnOrganizationsProjectAndLeavesTheOwnOneUnshared() throws {
        let organization = #"{"id":"op_1","name":"API","repository":"github.com/acme/api","servers":["github"],"skills":[],"rulePack":"Release rules","rules":4,"memory":"project","skipped":["left out"],"editedIn":"API is the organization's project, so it is changed in Memnox Cloud rather than here."}"#
        let shared = #"{"id":"prj_1","scope":"organization","organization":"# + organization + #","name":"API","path":"/code/api","declared":true,"opened":true,"agents":[],"agentsSeen":[],"sessions":{"total":0,"ended":0},"servers":[],"skills":[],"rules":{"count":0,"inForce":false},"instructions":[],"memoryScope":"project","openMissions":[],"openQuestions":0}"#
        let own = #"{"id":"prj_2","name":"Mine","path":"/code/mine","declared":false,"opened":false,"agents":[],"agentsSeen":[],"sessions":{"total":0,"ended":0},"servers":[],"skills":[],"rules":{"count":0,"inForce":false},"instructions":[],"memoryScope":"project","openMissions":[],"openQuestions":0}"#
        let response = try line(#"{"id":5,"ok":true,"projects":{"projects":["# + shared + "," + own + "]}}")
        let projects = try XCTUnwrap(response.projects?.projects)
        XCTAssertEqual(projects.first?.sharedBy?.rulePack, "Release rules")
        XCTAssertEqual(projects.first?.sharedBy?.rules, 4)
        XCTAssertNil(projects.first?.sharedBy?.description)
        XCTAssertNil(projects.last?.sharedBy)
        XCTAssertNil(projects.last?.scope)
    }

    func testWritesEachRequestWithOnlyTheFieldsItCarries() throws {
        var set = DaemonRequest(id: 6, method: .lanSet)
        set.lanOn = true
        let lan = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(set)) as? [String: Any])
        XCTAssertEqual(lan["method"] as? String, "lan-set")
        XCTAssertEqual(lan["lanOn"] as? Bool, true)

        var offer = DaemonRequest(id: 7, method: .personalSyncKeyOffer)
        offer.syncMachineId = "laptop"
        offer.syncFingerprint = "12345 67890 11121 31415 16171 81920"
        let offered = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(offer)) as? [String: Any])
        XCTAssertEqual(offered["syncMachineId"] as? String, "laptop")
        XCTAssertEqual(offered["syncFingerprint"] as? String, "12345 67890 11121 31415 16171 81920")
        XCTAssertNil(offered["syncKeep"])

        var resolve = DaemonRequest(id: 8, method: .personalSyncResolve)
        resolve.syncConflictId = "c1"
        resolve.syncKeep = SyncKeep.mine.rawValue
        let resolved = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(resolve)) as? [String: Any])
        XCTAssertEqual(resolved["syncKeep"] as? String, "mine")
        XCTAssertNil(resolved["lanOn"])
    }

    func testNamesEveryMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.lanStatus, .lanSet, .personalSyncStatus, .personalSyncNow, .personalSyncConflicts,
                                       .personalSyncResolve, .personalSyncKeyOffer, .personalSyncKeyAccept]
        XCTAssertEqual(methods.map(\.rawValue), ["lan-status", "lan-set", "personal-sync-status", "personal-sync-now",
                                                 "personal-sync-conflicts", "personal-sync-resolve", "personal-sync-key-offer",
                                                 "personal-sync-key-accept"])
    }
}
