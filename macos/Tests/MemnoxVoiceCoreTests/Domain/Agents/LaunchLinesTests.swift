import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/launch-lines.test.ts, so Launch says the same on every desktop.
final class LaunchLinesTests: XCTestCase {
    func testTakesAWholePathOnEitherSystemAndSaysWhatIsWrongWithAnother() {
        XCTAssertTrue(LaunchLines.isAbsoluteFolder("/code/memnox"))
        XCTAssertTrue(LaunchLines.isAbsoluteFolder("C:\\code\\memnox"))
        XCTAssertTrue(LaunchLines.isAbsoluteFolder("\\\\share\\code"))
        XCTAssertEqual(LaunchLines.folderProblem("code/memnox"), "Give the whole path, from the top of the drive.")
        XCTAssertEqual(LaunchLines.folderProblem(" "), "Choose the folder it opens in.")
        XCTAssertNil(LaunchLines.folderProblem("/code"))
    }

    func testSaysWhereItOpenedAndWhatItTyped() {
        let launched = AgentLaunched(agent: "claude-code", workingDirectory: "/code/app", line: "claude")
        XCTAssertEqual(LaunchLines.launched(launched, name: "Claude Code"), "Opened Claude Code in /code/app, typing claude.")
    }
}
