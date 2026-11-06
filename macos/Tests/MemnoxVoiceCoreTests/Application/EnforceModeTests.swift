import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Turning this Mac from watching to stopping: one unsigned call to the daemon, which only ever moves toward enforce,
/// and the home's step and badge read off the mode the daemon reports after it.
final class EnforceModeTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var conversation: Conversation!

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil))
    }

    func testAsksTheDaemonToEnforceUnsignedAndSaysWhereTheModeWent() async throws {
        link.answers["mode-enforce"] = [try line(#"{"id":1,"ok":true,"modeSet":{"was":"observe","now":"enforce"}}"#)]
        let outcome = await conversation.enforceMode()
        XCTAssertEqual(outcome, .enforcing(HomeModeSet(was: "observe", now: "enforce")))
        XCTAssertEqual(link.sent.last?.method, DaemonMethod.modeEnforce.rawValue)
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(HomeEnforce.line(outcome),
                       "This Mac now stops what a rule denies. memnox protect --observe in a terminal puts it back.")
    }

    func testAsksAfterSetupOnlyWhileTheMacObserves() {
        XCTAssertEqual(HomeEnforce.afterSetup(.observe),
                       "One more thing. Memnox is still in observing mode, so it records what a rule would stop but stops "
                       + "nothing yet. Do you want to switch to enforcing mode? Choose on your screen.")
        XCTAssertNil(HomeEnforce.afterSetup(.enforce))
        XCTAssertNil(HomeEnforce.afterSetup(nil))
    }

    func testSaysSoWhenTheMacAlreadyEnforced() {
        XCTAssertEqual(HomeEnforce.line(.enforcing(HomeModeSet(was: "enforce", now: "enforce"))),
                       "This Mac was already stopping what a rule denies.")
    }

    func testAnOlderDaemonOrNoneIsSaidPlainly() async throws {
        link.answers["mode-enforce"] = [try line(#"{"id":1,"ok":true}"#)]
        let older = await conversation.enforceMode()
        guard case .refused(let why) = older else { return XCTFail("expected a refusal, got \(older)") }
        XCTAssertTrue(why.contains("memnox protect --enforce"))
        link.unreachable = true
        let away = await conversation.enforceMode()
        XCTAssertEqual(away, .unreachable)
    }

    func testTheStepPressesToTurnOnStoppingAndClosesOnceTheDaemonEnforces() {
        var standing = HomeStanding()
        standing.mode = .observe
        let open = HomeSteps.steps(standing).first { $0.id == .enforce }
        XCTAssertEqual(open?.action, "Turn on stopping")
        XCTAssertEqual(open?.done, false)
        standing.mode = .enforce
        XCTAssertEqual(HomeSteps.steps(standing).first { $0.id == .enforce }?.done, true)
    }

    func testTheBadgeFollowsTheModeTheDaemonReports() {
        XCTAssertEqual(HomeMode.observe.badge, "Observing on this Mac")
        XCTAssertEqual(HomeMode.enforce.badge, "Enforcing on this Mac")
    }

    func testNoWordOfTheConfirmCarriesADash() {
        for copy in [HomeEnforce.title, HomeEnforce.message, HomeEnforce.detail, HomeEnforce.confirm, HomeEnforce.readFirst,
                     HomeEnforce.remote] {
            XCTAssertFalse(copy.contains("\u{2014}") || copy.contains("\u{2013}") || copy.contains(" - "), copy)
        }
    }
}
