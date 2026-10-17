import XCTest

@testable import MemnoxVoiceCore

/// One label for a held call wherever it shows, so the card, the sheet, the caption and the voice name it alike.
final class CallLabelTests: XCTestCase {
    func testThisMacsCallSaysYourMac() {
        XCTAssertEqual(CallLabel.label("Claude Code", at: .thisMac), "Claude Code on your Mac")
    }

    func testAServersCallNamesTheServer() {
        XCTAssertEqual(CallLabel.label("codex", at: .server("build-box")), "codex on build-box")
    }

    func testATeamCallSaysWhoseTeamItCameFrom() {
        XCTAssertEqual(CallLabel.label("codex", at: .team(machine: "build-box", person: "Ana")), "codex on build-box, from Ana's team")
    }

    func testATeamCallWithNobodyNamedSaysYourTeam() {
        XCTAssertEqual(CallLabel.label("codex", at: .team(machine: "build-box", person: nil)), "codex on build-box, from your team")
        XCTAssertEqual(CallLabel.label("codex", at: .team(machine: "build-box", person: "  ")), "codex on build-box, from your team")
    }

    func testBlankNamesNeverLeaveAGap() {
        XCTAssertEqual(CallLabel.label(" ", at: .server("")), "an agent on a server")
        XCTAssertEqual(CallLabel.label("codex", at: .team(machine: "", person: nil)), "codex on a teammate's machine, from your team")
    }

    func testADaemonEventsPlaceIsTheServerThatRaisedItElseThisMac() {
        XCTAssertEqual(CallPlace.raised(on: "build-box"), .server("build-box"))
        XCTAssertEqual(CallPlace.raised(on: nil), .thisMac)
        XCTAssertEqual(CallPlace.raised(on: " "), .thisMac)
    }

    func testTheMachineAloneIsWhatCallsAreGroupedBy() {
        XCTAssertEqual(CallPlace.thisMac.machine, "your Mac")
        XCTAssertEqual(CallPlace.server("build-box").machine, "build-box")
        XCTAssertEqual(CallPlace.team(machine: "Ana's Mac", person: "Ana").machine, "Ana's Mac")
    }

    func testTheTouchIDSheetNamesTheCallAndHowFarTheYesReaches() {
        let label = "codex on build-box, from Ana's team"
        XCTAssertEqual(CallLabel.touchIDReason(label, what: "Codex wants to push to main.", answer: .once),
                       "allow codex on build-box, from Ana's team once: Codex wants to push to main")
        XCTAssertEqual(CallLabel.touchIDReason(label, what: "git push", answer: .session),
                       "allow codex on build-box, from Ana's team for this session: git push")
        XCTAssertEqual(CallLabel.touchIDReason("Claude Code on your Mac", what: " ", answer: .deny), "deny Claude Code on your Mac")
    }

    func testAWorkspaceCallIsLabelledByItsMachineAndOwner() throws {
        let named = try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(heldJSON(ownerName: "Ana").utf8))
        XCTAssertEqual(named.who, "codex on build-box, from Ana's team")
        let unnamed = try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(heldJSON(machineLabel: nil).utf8))
        XCTAssertEqual(unnamed.who, "codex on mch_91c2, from your team")
    }
}
