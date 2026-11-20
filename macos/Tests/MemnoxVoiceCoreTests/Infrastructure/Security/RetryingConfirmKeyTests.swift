import XCTest

@testable import MemnoxVoiceCore

/// A confirmation key that could not be opened is tried again at the next need, and kept once it opens.
final class RetryingConfirmKeyTests: XCTestCase {
    private struct Refused: Error {}

    func testOpensAgainAfterARefusalAndKeepsTheKeyOnceOpened() async throws {
        let inner = SoftwareConfirmKey()
        var attempts = 0
        let key = RetryingConfirmKey {
            attempts += 1
            if attempts == 1 { throw Refused() }
            return inner
        }
        XCTAssertEqual(attempts, 1)
        let signature = try await key.sign("memnox-confirm:v1:7:allow", reason: "allow it")
        XCTAssertNotNil(signature)
        XCTAssertEqual(key.publicPoint, inner.publicPoint)
        XCTAssertEqual(attempts, 2)
    }

    func testSaysNoAndOffersNoPointWhileTheKeyStaysClosed() async throws {
        let key = RetryingConfirmKey { throw Refused() }
        XCTAssertEqual(key.publicPoint, "")
        let signature = try await key.sign("memnox-confirm:v1:7:allow", reason: "allow it")
        XCTAssertNil(signature)
        let batch = try await key.sign(["a", "b"], reason: "allow both")
        XCTAssertNil(batch)
    }
}
