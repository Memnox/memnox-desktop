import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Telling a session in a terminal from one in an agent panel, so a follow up never opens a new chat.
final class TerminalFrontTests: XCTestCase {
    func testAnAgentInFrontMeansTheSessionLivesInThatTerminal() {
        XCTAssertTrue(TerminalFront.agentInFront("Ss   -zsh\nS+   claude\n"))
        XCTAssertFalse(TerminalFront.agentInFront("Ss+  -zsh\nS    claude\n"))
        XCTAssertFalse(TerminalFront.agentInFront(""))
    }

    func testKnowsANativeInstallWhoseBinaryIsNamedForItsVersion() {
        XCTAssertTrue(TerminalFront.agentInFront("Ss   -zsh\nS+   /Users/m/.local/share/claude/versions/2.1.3\n"))
        // A shell under a node folder is not an agent.
        XCTAssertFalse(TerminalFront.agentInFront("S+   /opt/node/bin/zsh\n"))
    }
}
