import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The in memory key signs in the shapes the runtime verifies.
final class SoftwareConfirmKeyTests: XCTestCase {
    func testTheSoftwareKeyShapesMatchTheRuntime() async throws {
        let key = SoftwareConfirmKey()
        let point = try XCTUnwrap(Data(base64Encoded: key.publicPoint))
        XCTAssertEqual(point.count, 65)
        XCTAssertEqual(point.first, 0x04)
        let signature = try await key.sign("m", reason: "r")
        let der = try XCTUnwrap(signature.flatMap { Data(base64Encoded: $0) })
        let publicKey = try P256.Signing.PublicKey(x963Representation: point)
        XCTAssertTrue(publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: Data("m".utf8)))
    }
}
