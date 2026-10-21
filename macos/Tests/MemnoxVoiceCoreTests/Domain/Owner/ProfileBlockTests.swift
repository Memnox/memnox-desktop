import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Taking the app's PATH lines back out of a shell profile, and nothing of the person's with them.
final class ProfileBlockTests: XCTestCase {
    /// Exactly what unpack.sh appends.
    private static let block = "\n\(ProfileBlock.begin)\n# Added by Memnox.app so a terminal finds memnox. Delete these lines to undo.\nexport PATH=\"/Users/me/.memnox/node/bin:$PATH\"\n\(ProfileBlock.end)\n"

    func testPutsAProfileBackAsItWasBeforeTheBlock() {
        let mine = "export EDITOR=vim\nalias ll='ls -l'\n"
        XCTAssertEqual(ProfileBlock.without(mine + Self.block), mine)
    }

    func testKeepsWhatWasWrittenAfterTheBlock() {
        let mine = "export EDITOR=vim\n"
        let later = "eval \"$(starship init zsh)\"\n"
        XCTAssertEqual(ProfileBlock.without(mine + Self.block + later), mine + later)
    }

    func testEmptiesAProfileThatHeldOnlyTheBlock() {
        XCTAssertEqual(ProfileBlock.without(Self.block), "")
    }

    func testKeepsTheLastLineWholeWhenItHadNoNewline() {
        XCTAssertEqual(ProfileBlock.without("export EDITOR=vim" + Self.block), "export EDITOR=vim\n")
    }

    func testLeavesAProfileWithoutTheBlockAlone() {
        XCTAssertNil(ProfileBlock.without("export EDITOR=vim\n"))
    }

    func testLeavesAProfileWhoseBlockLostItsEnd() {
        XCTAssertNil(ProfileBlock.without("export EDITOR=vim\n\n\(ProfileBlock.begin)\nexport PATH=x\nalias mine=1\n"))
    }
}
