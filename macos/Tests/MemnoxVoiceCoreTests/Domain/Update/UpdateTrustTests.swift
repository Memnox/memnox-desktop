import XCTest

@testable import MemnoxVoiceCore

/// Which downloaded app may replace the running one, held to the Apple team that signs Memnox.
final class UpdateTrustTests: XCTestCase {
    private let team = "ABCDE12345"
    private var released: AppSignature { AppSignature(isIntact: true, team: team) }
    private let local = AppSignature(isIntact: true, team: nil)

    func testTakesAnUpdateFromTheSameTeam() {
        XCTAssertEqual(UpdateTrust.verdict(for: released, running: released, pinned: nil), .trusted)
    }

    func testRefusesAnUpdateFromAnotherTeam() {
        let stranger = AppSignature(isIntact: true, team: "ZZZZZ99999")
        XCTAssertEqual(UpdateTrust.verdict(for: stranger, running: released, pinned: nil),
                       .strangerTeam(expected: team, found: "ZZZZZ99999"))
    }

    func testRefusesAnUnsignedUpdateOnceMemnoxHasATeam() {
        XCTAssertEqual(UpdateTrust.verdict(for: local, running: released, pinned: nil),
                       .strangerTeam(expected: team, found: nil))
    }

    func testRefusesABrokenSealWhoeverSignedIt() {
        let tampered = AppSignature(isIntact: false, team: team)
        XCTAssertEqual(UpdateTrust.verdict(for: tampered, running: local, pinned: nil), .broken)
    }

    func testAPreviewHoldsItsUpdateToTheTeamItsBuildNamed() {
        XCTAssertEqual(UpdateTrust.verdict(for: released, running: local, pinned: team), .trusted)
        XCTAssertEqual(UpdateTrust.verdict(for: local, running: local, pinned: team), .strangerTeam(expected: team, found: nil))
    }

    func testTheRunningTeamOutranksThePinnedOne() {
        XCTAssertEqual(UpdateTrust.expectedTeam(running: released, pinned: "OTHER00000"), team)
    }

    func testAPreviewWithNoTeamTakesAnyIntactUpdate() {
        XCTAssertEqual(UpdateTrust.verdict(for: released, running: local, pinned: "  "), .trusted)
        XCTAssertEqual(UpdateTrust.verdict(for: local, running: local, pinned: nil), .trusted)
    }

    func testABlankTeamIsNoTeam() {
        XCTAssertNil(AppSignature(isIntact: true, team: "").team)
    }
}
