import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The local network and shared projects as the runtime's daemon/lan.ts and daemon/projects.ts write them.
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
        XCTAssertNil(lan["syncKeep"])
    }

    func testNamesEveryMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.lanStatus, .lanSet]
        XCTAssertEqual(methods.map(\.rawValue), ["lan-status", "lan-set"])
    }
}
