import Foundation
import Security
import XCTest

@testable import MemnoxVoiceCore

/// The team credential: kept whole, replaced by a newer sign in, gone on sign out, and apart from the paired servers.
final class PersonCredentialTests: XCTestCase {
    func testTheMemoryStoreKeepsOneCredential() throws {
        let store = MemoryPersonCredential()
        try store.save(signedInCredential())
        try store.save(signedInCredential(workspaces: ["ws_2"]))
        XCTAssertEqual(store.load()?.workspaces, ["ws_2"])
        store.delete()
        XCTAssertNil(store.load())
    }

    func testTheCredentialSurvivesTheKeychainBesideThePairedServers() throws {
        let suffix = UUID().uuidString
        let store = KeychainPersonCredential(service: "\(KeychainPersonCredential.defaultService).test.\(suffix)")
        let servers = KeychainPairedServers(service: "\(KeychainPairedServers.defaultService).test.\(suffix)")
        do {
            try store.save(signedInCredential())
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain {
            throw XCTSkip("this run cannot reach a keychain: OSStatus \(error.code)")
        }
        defer { store.delete() }
        XCTAssertEqual(store.load(), signedInCredential())
        XCTAssertEqual(servers.all(), [])
        store.delete()
        XCTAssertNil(store.load())
    }

    func testTheServicesAreApart() {
        XCTAssertNotEqual(KeychainPersonCredential.defaultService, KeychainPairedServers.defaultService)
    }
}
