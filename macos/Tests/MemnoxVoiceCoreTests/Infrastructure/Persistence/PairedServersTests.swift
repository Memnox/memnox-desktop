import Foundation
import Security
import XCTest

@testable import MemnoxVoiceCore

/// The servers this Mac paired with: one record per machine, the newest pairing kept, and a forgotten one gone.
final class PairedServersTests: XCTestCase {
    func testKeepsOneRecordPerServerReplacingAnEarlierPairing() throws {
        let store = MemoryPairedServers()
        try store.save(pairedServer(deviceId: "dev_old", pairedAt: Date(timeIntervalSince1970: 1)))
        try store.save(pairedServer("mch_other", name: "other", pairedAt: Date(timeIntervalSince1970: 2)))
        try store.save(pairedServer(deviceId: "dev_new", pairedAt: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(store.all().map(\.machineId), ["mch_other", "mch_vps"])
        XCTAssertEqual(store.all().last?.deviceId, "dev_new")
    }

    func testForgetsOneServerAndLeavesTheRest() throws {
        let store = MemoryPairedServers([pairedServer(), pairedServer("mch_other", name: "other")])
        store.forget(machineId: "mch_vps")
        XCTAssertEqual(store.all().map(\.machineId), ["mch_other"])
    }

    func testARecordSurvivesTheKeychainWholeSecretsIncluded() throws {
        let store = KeychainPairedServers(service: "com.memnox.voice.servers.test.\(UUID().uuidString)")
        let server = pairedServer()
        do {
            try store.save(server)
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain {
            throw XCTSkip("this run cannot reach a keychain: OSStatus \(error.code)")
        }
        defer { store.forget(machineId: server.machineId) }
        XCTAssertEqual(store.all(), [server])
        try store.save(pairedServer(deviceId: "dev_again"))
        XCTAssertEqual(store.all().map(\.deviceId), ["dev_again"])
        store.forget(machineId: server.machineId)
        XCTAssertEqual(store.all(), [])
    }
}
